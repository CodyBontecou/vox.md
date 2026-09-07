import Foundation
import SwiftParser
import SwiftSyntax

// This is an architectural budget, NOT a prediction of an iOS stack limit.
// Small, concrete sections make metadata growth local; hardware smoke is still required.
private let sectionTokenBudget = 600

private final class CaptureViewStructureVisitor: SyntaxVisitor {
    var errors: [String] = []
    private var owners: [String] = []

    init() { super.init(viewMode: .sourceAccurate) }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        owners.append(node.name.text)
        if node.name.text == "CaptureViewSection" || node.name.text == "QuickCaptureCanvas" {
            if node.genericParameterClause != nil {
                errors.append("\(node.name): must remain non-generic; generic slots propagate child metadata")
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) { owners.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        owners.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) { owners.removeLast() }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let accessor = binding.accessorBlock,
                  let type = binding.typeAnnotation?.type else { continue }
            check(name: binding.pattern.trimmedDescription, type: type, body: Syntax(accessor))
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let type = node.signature.returnClause?.type, let body = node.body {
            check(name: node.name.text, type: type, body: Syntax(body))
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let calledName = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
            ?? node.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
        if calledName == "AnyView", owners.last != "CaptureViewSection" {
            errors.append("\(owners.last ?? "file"): put erasure in CaptureViewSection, not at call sites")
        }
        return .visitChildren
    }

    private func check(name: String, type: TypeSyntax, body: Syntax) {
        let typeTokens = type.tokens(viewMode: .sourceAccurate).map(\.text)
        let result = typeTokens.joined()
        let isOpaqueView = typeTokens.contains("some") && typeTokens.contains("View")
        let isRawErasure = typeTokens.last == "AnyView"
        let owner = owners.last ?? "file"
        let isCoordinator = owner == "QuickCaptureView"
        if isCoordinator && (isOpaqueView || isRawErasure || name == "body")
            && result != "CaptureViewSection" {
            errors.append("\(owner).\(name): return CaptureViewSection; opaque helpers recreate the launch-crash chain")
        }
        if owner == "CaptureViewSection" && name == "body" && result != "AnyView" {
            errors.append("CaptureViewSection.body: must return AnyView to keep metadata bounded")
        }
        guard name == "body" || result == "CaptureViewSection" || isOpaqueView || isRawErasure else {
            return
        }
        let count = Array(body.tokens(viewMode: .sourceAccurate)).count
        if count > sectionTokenBudget {
            errors.append("\(owner).\(name): \(count) syntax tokens exceeds \(sectionTokenBudget); split into concrete sections")
        }
    }
}

private func validate(_ source: String) -> [String] {
    let syntax = Parser.parse(source: source)
    guard !syntax.hasError else { return ["Swift syntax is invalid; refusing to skip structural validation"] }
    let visitor = CaptureViewStructureVisitor()
    visitor.walk(syntax)
    return visitor.errors
}

private func selfTest() throws {
    let fixtures: [(String, String, Bool)] = [
        ("concrete coordinator", "struct QuickCaptureView { var body: CaptureViewSection { section }; var section: CaptureViewSection { CaptureViewSection { Text(\"ok\") } } }", true),
        ("opaque body", "struct QuickCaptureView { var body: some View { Text(\"oops\") } }", false),
        ("new opaque helper", "struct QuickCaptureView { @ViewBuilder private var toast: some View { Text(\"oops\") } }", false),
        ("opaque function in extension", "extension QuickCaptureView { func banner(_ text: String) -> some View { Text(text) } }", false),
        ("raw erasure", "struct QuickCaptureView { var toast: AnyView { AnyView(Text(\"oops\")) } }", false),
        ("raw erasure at call site", "struct QuickCaptureView { var body: CaptureViewSection { CaptureViewSection { AnyView(Text(\"oops\")) } } }", false),
        ("qualified erasure", "struct QuickCaptureView { var toast: SwiftUI.AnyView { SwiftUI.AnyView(Text(\"oops\")) } }", false),
        ("multiline opaque result", "struct QuickCaptureView { var toast: some\\nSwiftUI.View { Text(\"oops\") } }".replacingOccurrences(of: "\\n", with: "\n"), false),
        ("generic boundary", "struct CaptureViewSection<Content: View>: View { let content: Content; var body: some View { content } }", false),
        ("generic canvas", "struct QuickCaptureCanvas<Content: View>: View { let content: Content; var body: some View { content } }", false),
        ("nominal child", "struct QuickCaptureSentToast: View { var body: some View { Text(\"Undo\") } }", true),
        ("comments and strings", "struct QuickCaptureView { /* var body: some View { } */ var body: CaptureViewSection { CaptureViewSection { Text(\"some View; AnyView(\") } } }", true),
        ("malformed source", "struct QuickCaptureView { var body:", false),
        ("unbounded single section", "struct QuickCaptureView { var body: CaptureViewSection { CaptureViewSection { VStack { " + String(repeating: "Text(\"row\")\n", count: 160) + " } } } }", false),
    ]
    for (name, source, expectedPass) in fixtures {
        if name != "malformed source" && Parser.parse(source: source).hasError {
            throw NSError(domain: "Invalid Swift in checker fixture: \(name)", code: 1)
        }
        let errors = validate(source)
        guard errors.isEmpty == expectedPass else {
            throw NSError(domain: "CaptureViewStructure", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Fixture '\(name)' unexpectedly \(errors.isEmpty ? "passed" : "failed"): \(errors)"])
        }
    }
    print("Capture structure checker: \(fixtures.count) positive/negative fixtures passed")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        try selfTest()
    } else {
        guard !arguments.isEmpty else { throw NSError(domain: "Usage: validator file.swift ...", code: 2) }
        var failed = false
        for path in arguments {
            for error in validate(try String(contentsOfFile: path, encoding: .utf8)) {
                fputs("\(path): error: \(error)\n", stderr)
                failed = true
            }
        }
        if failed { exit(1) }
        print("Capture view structure passed (\(arguments.count) files; budget \(sectionTokenBudget) tokens per section)")
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}

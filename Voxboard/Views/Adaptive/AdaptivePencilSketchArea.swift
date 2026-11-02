import PencilKit
import SwiftUI
import VoxboardShared

/// iPad "Draw with Pencil" area inline under the composer. Strokes land on a
/// live PencilKit canvas; "Add sketch" stages it as a sketch attachment through
/// the same path as the Sketch sheet (`CaptureSketchEditor.sketchPayload` →
/// `QuickCaptureViewModel.stageSketch`).
struct AdaptivePencilSketchArea: View {
    @Bindable var viewModel: QuickCaptureViewModel

    @State private var drawing = PKDrawing()
    @State private var clearToken = 0
    @State private var isSaving = false

    private var hasStrokes: Bool { !drawing.strokes.isEmpty }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AdaptiveInlinePencilCanvas(drawing: $drawing, clearToken: clearToken)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if !hasStrokes {
                        VStack(spacing: 6) {
                            Image(systemName: "pencil.tip")
                                .font(.system(size: 18, weight: .medium))
                            Text("Draw with Pencil")
                                .font(Geist.body(.subheadline))
                        }
                        .foregroundStyle(Geist.muted)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            hasStrokes ? Geist.border : Geist.Palette.gray600,
                            style: StrokeStyle(lineWidth: 1, dash: hasStrokes ? [] : [5, 4])
                        )
                        .allowsHitTesting(false)
                }

            if hasStrokes {
                HStack(spacing: 8) {
                    Button("Clear") { clear() }
                        .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
                        .accessibilityIdentifier("adaptive_pencil_clear")
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Add sketch")
                        }
                    }
                    .buttonStyle(GeistButtonStyle(variant: .primary, size: .small))
                    .disabled(isSaving || !viewModel.canChangeCaptureRoute)
                    .accessibilityIdentifier("adaptive_pencil_add")
                }
                .fixedSize()
                .padding(10)
                .transition(.opacity)
            }
        }
        // iPad board: a 140pt card in the 520pt attachment grid under the text.
        .frame(height: 140)
        .frame(maxWidth: 520, alignment: .leading)
        .animation(.easeOut(duration: 0.15), value: hasStrokes)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Sketch area"))
        .accessibilityHint(Text("Draw with Apple Pencil or your finger, then add the sketch to this capture."))
        .accessibilityIdentifier("adaptive_pencil_area")
    }

    private func clear() {
        drawing = PKDrawing()
        clearToken += 1
    }

    private func save() {
        guard let payload = CaptureSketchEditor.sketchPayload(for: drawing),
              viewModel.requireCaptureRouteAvailable() else { return }
        isSaving = true
        Task {
            viewModel.isProcessingMedia = true
            await viewModel.stageSketch(drawingData: payload.drawing, previewData: payload.preview)
            viewModel.isProcessingMedia = false
            isSaving = false
            clear()
        }
    }
}

/// Calm inline canvas: a black pen, no floating tool picker, any input unless
/// the person turned on "Only Draw with Apple Pencil".
private struct AdaptiveInlinePencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let clearToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.drawingPolicy = UIPencilInteraction.prefersPencilOnlyDrawing ? .pencilOnly : .anyInput
        canvas.backgroundColor = .white
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.accessibilityIdentifier = "adaptive_pencil_canvas"
        context.coordinator.clearToken = clearToken
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if context.coordinator.clearToken != clearToken {
            context.coordinator.clearToken = clearToken
            canvas.drawing = PKDrawing()
        } else if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing
        var clearToken = 0
        init(drawing: Binding<PKDrawing>) { _drawing = drawing }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { drawing = canvasView.drawing }
    }
}

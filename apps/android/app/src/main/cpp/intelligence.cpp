#include <jni.h>
#include "llama.h"
#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
std::mutex inference_mutex;
std::atomic<int64_t> active_request{0}, cancelled_request{0};
struct Deadline {
    std::chrono::steady_clock::time_point until;
    int64_t request;
};
bool aborted(void * state) {
    auto * deadline = static_cast<Deadline *>(state);
    return cancelled_request.load() == deadline->request || std::chrono::steady_clock::now() >= deadline->until;
}
std::string bytes(JNIEnv * env, jbyteArray data) {
    const auto size = env->GetArrayLength(data);
    std::string result(size, '\0');
    env->GetByteArrayRegion(data, 0, size, reinterpret_cast<jbyte *>(result.data()));
    return result;
}
void append_tokens(const llama_vocab * vocab, const std::string & text, bool special, std::vector<llama_token> & into) {
    auto count = llama_tokenize(vocab, text.data(), text.size(), nullptr, 0, false, special);
    if (count >= 0) return;
    std::vector<llama_token> tokens(-count);
    count = llama_tokenize(vocab, text.data(), text.size(), tokens.data(), tokens.size(), false, special);
    if (count < 0) throw std::runtime_error("instructionTokenization");
    into.insert(into.end(), tokens.begin(), tokens.begin() + count);
}
}
extern "C" JNIEXPORT void JNICALL
Java_md_vox_android_platformservices_NativeInstructionRuntime_cancel(JNIEnv *, jobject, jlong request) {
    if (active_request.load() == request) cancelled_request.store(request);
}
extern "C" JNIEXPORT jbyteArray JNICALL
Java_md_vox_android_platformservices_NativeInstructionRuntime_generate(
    JNIEnv * env, jobject, jstring path, jbyteArray system, jbyteArray user, jint maximum, jlong timeout, jlong request) {
    std::lock_guard<std::mutex> lock(inference_mutex);
    active_request.store(request);
    struct Reset { ~Reset() { active_request.store(0); } } reset;
    try {
        if (maximum < 1 || maximum > 1024 || timeout < 1 || timeout > 90000) throw std::runtime_error("instructionLimits");
        static std::once_flag initialized;
        std::call_once(initialized, [] {
            llama_log_set([](ggml_log_level, const char *, void *) {}, nullptr);
            llama_backend_init();
        });
        const char * characters = env->GetStringUTFChars(path, nullptr);
        if (!characters) return nullptr;
        const std::string filename(characters);
        env->ReleaseStringUTFChars(path, characters);
        Deadline deadline{std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout), request};
        auto model_params = llama_model_default_params();
        model_params.n_gpu_layers = 0;
        std::unique_ptr<llama_model, decltype(&llama_model_free)> model(
            llama_model_load_from_file(filename.c_str(), model_params), llama_model_free);
        if (!model) throw std::runtime_error("instructionModelLoad");
        auto context_params = llama_context_default_params();
        context_params.n_ctx = 4096;
        context_params.n_batch = 128;
        context_params.n_ubatch = 128;
        context_params.n_threads = 4;
        context_params.n_threads_batch = 4;
        context_params.abort_callback = aborted;
        context_params.abort_callback_data = &deadline;
        std::unique_ptr<llama_context, decltype(&llama_free)> context(llama_init_from_model(model.get(), context_params), llama_free);
        if (!context) throw std::runtime_error("instructionContext");
        const auto * vocab = llama_model_get_vocab(model.get());
        std::vector<llama_token> tokens;
        // Only our fixed role markers are special tokens. Capture/instruction content
        // can contain ChatML strings without creating an assistant/system turn.
        append_tokens(vocab, "<|im_start|>system\n", true, tokens);
        append_tokens(vocab, bytes(env, system), false, tokens);
        append_tokens(vocab, "<|im_end|>\n<|im_start|>user\n", true, tokens);
        append_tokens(vocab, bytes(env, user), false, tokens);
        append_tokens(vocab, "<|im_end|>\n<|im_start|>assistant\n", true, tokens);
        if (tokens.size() + maximum > llama_n_ctx(context.get())) throw std::runtime_error("instructionContextLimit");
        for (size_t start = 0; start < tokens.size(); start += 128) {
            if (aborted(&deadline)) throw std::runtime_error("instructionAborted");
            const auto count = static_cast<int32_t>(std::min(size_t(128), tokens.size() - start));
            if (llama_decode(context.get(), llama_batch_get_one(tokens.data() + start, count)) != 0) throw std::runtime_error("instructionDecode");
        }
        std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(llama_sampler_init_greedy(), llama_sampler_free);
        std::string output;
        bool complete = false;
        for (int index = 0; index < maximum; ++index) {
            if (aborted(&deadline)) throw std::runtime_error("instructionAborted");
            auto token = llama_sampler_sample(sampler.get(), context.get(), -1);
            if (llama_vocab_is_eog(vocab, token)) { complete = true; break; }
            char buffer[256];
            auto count = llama_token_to_piece(vocab, token, buffer, sizeof(buffer), 0, false);
            if (count < 0) throw std::runtime_error("instructionTokenPiece");
            output.append(buffer, count);
            if (llama_decode(context.get(), llama_batch_get_one(&token, 1)) != 0) throw std::runtime_error("instructionDecode");
        }
        if (!complete) throw std::runtime_error("instructionOutputLimit");
        auto result = env->NewByteArray(output.size());
        if (result) env->SetByteArrayRegion(result, 0, output.size(), reinterpret_cast<const jbyte *>(output.data()));
        return result;
    } catch (const std::exception & error) {
        env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), error.what());
        return nullptr;
    }
}

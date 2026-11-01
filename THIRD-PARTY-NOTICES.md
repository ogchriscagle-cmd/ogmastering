# Bundled components

OG Mastering runs the following independent third-party components locally. Their respective licenses apply to those components. Bundled JavaScript packages retain their license and notice files in `bin/detection/node_modules`; Node's notices are in `bin/detection/node-v24.13.0-win-x64/LICENSE`.

- FFmpeg 9.0.2 essentials build from gyan.dev, GPL v3. Build/readme, license and documentation are retained in `notices/ffmpeg` in the extracted application. Exact upstream source revision: https://github.com/FFmpeg/FFmpeg/commit/946fcce07b. The corresponding source archive is supplied with the GitHub release. Build configuration is in the bundled README.
- Node.js 24.13.0: https://nodejs.org/dist/v24.13.0/ and https://github.com/nodejs/node/tree/v24.13.0. MIT license and bundled third-party notices accompany the runtime.
- Hugging Face Transformers.js 3.8.1: https://github.com/huggingface/transformers.js/tree/3.8.1. Apache-2.0; its package retains LICENSE and source.
- ONNX Runtime and Sharp and their included dependencies retain the notices supplied with their npm packages.
- Xenova/clap-htsat-unfused ONNX model conversion: https://huggingface.co/Xenova/clap-htsat-unfused. Original LAION CLAP model and project: https://huggingface.co/laion/clap-htsat-unfused and https://github.com/LAION-AI/CLAP. Model weights are unchanged and used for local zero-shot audio classification. Suggestions are not guaranteed or calibrated probabilities.

The EXE is a self-extracting application bundle. Its extraction directory contains these notices and editable app source. It uses the Windows-included .NET Framework and Windows PowerShell to launch the WPF interface. It does not install a system service or upload audio.

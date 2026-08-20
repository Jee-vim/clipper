{pkgs ? import <nixpkgs> {}}: let
  modelDir = "$HOME/.cache/whisper-models";
  modelFile = "${modelDir}/ggml-medium.bin";
in
  pkgs.mkShell {
    buildInputs = with pkgs; [
      deno
      ffmpeg
      yt-dlp
      whisper-cpp
    ];

    shellHook = ''
      mkdir -p "${modelDir}"
      if [ ! -f "${modelFile}" ]; then
        echo "[INFO] Downloading ggml-medium.bin model..."
        curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin" \
             -o "${modelFile}"
        echo "[INFO] Model downloaded to ${modelFile}"
      fi
    '';
  }

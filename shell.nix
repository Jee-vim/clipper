{pkgs ? import <nixpkgs> {}}: let
  modelFile = "${toString pkgs.homedir}/.cache/whisper-models/ggml-medium.bin";
in
  pkgs.mkShell {
    buildInputs = with pkgs; [
      ffmpeg
      yt-dlp
      whisper-cpp
    ];

    shellHook = ''
      mkdir -p ~/.cache/whisper-models
      if [ ! -f "$HOME/.cache/whisper-models/ggml-medium.bin" ]; then
        echo "Downloading ggml-medium.bin model..."
        curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin" \
             -o "$HOME/.cache/whisper-models/ggml-medium.bin"
        echo "Model downloaded to $HOME/.cache/whisper-models/ggml-medium.bin"
      fi
    '';
  }

{pkgs ? import <nixpkgs> {}}: let
  modelDir = "$HOME/.cache/whisper-models";
  modelFile = "${modelDir}/ggml-medium.bin";
in
  pkgs.mkShell {
    buildInputs = with pkgs; [
      deno
      ffmpeg
      whisper-cpp
      python3
      curl
    ];

    shellHook = ''
      mkdir -p "${modelDir}"
      if [ ! -f "${modelFile}" ]; then
        echo "[INFO] Downloading ggml-medium.bin model..."
        curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin" \
             -o "${modelFile}"
        echo "[INFO] Model downloaded to ${modelFile}"
      fi

      LOCAL_BIN="$PWD/.local/bin"
      mkdir -p "$LOCAL_BIN"
      if [ ! -x "$LOCAL_BIN/yt-dlp" ]; then
        echo "[INFO] Downloading latest yt-dlp..."
        curl -L "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" \
             -o "$LOCAL_BIN/yt-dlp"
        chmod +x "$LOCAL_BIN/yt-dlp"
      fi
      "$LOCAL_BIN/yt-dlp" -U >/dev/null 2>&1 || true
      export PATH="$LOCAL_BIN:$PATH"
    '';
  }

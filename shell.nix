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
      # TTS dependencies (Chatterbox / torch)
      uv
      python312
      stdenv.cc.cc.lib
      zlib
      libsndfile
      espeak-ng
    ];

    shellHook = ''
      export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.zlib}/lib:${pkgs.libsndfile}/lib:$LD_LIBRARY_PATH"

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

      # TTS venv (lazy: only needed for --story)
      if [ ! -d .venv ]; then
        uv venv --python ${pkgs.python312}/bin/python .venv
        uv pip install --python .venv/bin/python \
          chatterbox-tts soundfile torchaudio
      fi
      source .venv/bin/activate

      # Pre-fetch Chatterbox model weights into the HF cache (cached; fast on re-entry)
      python3 -c "from huggingface_hub import snapshot_download; snapshot_download('ResembleAI/chatterbox')" || true
    '';
  }

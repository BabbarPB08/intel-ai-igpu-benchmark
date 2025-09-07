#!/bin/bash
# Benchmark script: CPU (libx265) or Intel iGPU (QSV) encoding
# Usage:
#   ./benchmark_qsv.sh input.mp4 on-cpu
#   ./benchmark_qsv.sh input.mp4 on-igpu

INPUT="$1"
MODE="$2"

if [[ -z "$INPUT" || -z "$MODE" ]]; then
    echo "Usage: $0 input_video.mp4 [on-cpu|on-igpu]"
    exit 1
fi

OUTPUT_CPU="output_cpu_hevc.mp4"
OUTPUT_QSV="output_qsv_h264.mp4"

run_ffmpeg() {
    local CMD="$1"
    local OUT="$2"

    START=$(date +%s.%N)
    LOG=$(mktemp)
    eval "$CMD" 2> "$LOG"
    END=$(date +%s.%N)
    TIME=$(echo "$END - $START" | bc)

    # Extract FPS and speed from ffmpeg log
    FPS=$(grep -oP "fps=\s*\K[0-9.]+" "$LOG" | tail -1)
    SPEED=$(grep -oP "speed=\s*\K[0-9.]+x" "$LOG" | tail -1)

    # Fallback: calculate FPS manually if missing
    if [[ -z "$FPS" ]]; then
        TOTAL_FRAMES=$(grep -oP "frame=\s*\K[0-9]+" "$LOG" | tail -1)
        if [[ -n "$TOTAL_FRAMES" && $(echo "$TIME > 0" | bc) -eq 1 ]]; then
            FPS=$(echo "scale=2; $TOTAL_FRAMES / $TIME" | bc)
        else
            FPS="N/A"
        fi
    fi
    [[ -z "$SPEED" ]] && SPEED="N/A"

    rm -f "$LOG"
    echo "$TIME|$FPS|$SPEED"
}

case "$MODE" in
    on-cpu)
        echo "==========================================="
        echo "Benchmark: CPU encoding (libx265)"
        echo "Input file: $INPUT"
        echo "==========================================="
        RESULT=$(run_ffmpeg "ffmpeg -y -i \"$INPUT\" -c:v libx265 -preset medium -crf 28 -b:v 5M \"$OUTPUT_CPU\"" "$OUTPUT_CPU")
        IFS="|" read -r TIME FPS SPEED <<< "$RESULT"
        echo "CPU encoding done in ${TIME} sec | ${FPS} fps | ${SPEED} | Codec: libx265 (HEVC)"
        ;;

    on-igpu)
        echo "==========================================="
        echo "Benchmark: Intel iGPU encoding (QSV)"
        echo "Input file: $INPUT"
        echo "==========================================="
        RESULT=$(run_ffmpeg "ffmpeg -y -init_hw_device qsv=hw -filter_hw_device hw -i \"$INPUT\" -vf \"scale=1920:1080,format=nv12,hwupload\" -c:v h264_qsv -b:v 5M \"$OUTPUT_QSV\"" "$OUTPUT_QSV")
        IFS="|" read -r TIME FPS SPEED <<< "$RESULT"
        echo "QSV encoding done in ${TIME} sec | ${FPS} fps | ${SPEED} | Codec: h264_qsv"
        echo "Tip: Run 'sudo intel_gpu_top' in another terminal to monitor GPU usage."
        ;;

    *)
        echo "Invalid mode: $MODE"
        echo "Valid options: on-cpu | on-igpu"
        exit 1
        ;;
esac

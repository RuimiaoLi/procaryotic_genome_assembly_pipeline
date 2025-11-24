#!/bin/bash

# Enhanced Simplified Assembly Runner
# Usage: ./run_assembly.sh reads_1.fastq.gz reads_2.fastq.gz output_dir [options]

# Display help information
usage() {
    echo "Enhanced Genome Assembly Pipeline - Simplified Runner"
    echo ""
    echo "Usage: $0 read1.fastq.gz read2.fastq.gz output_dir [options]"
    echo ""
    echo "Required parameters:"
    echo "  read1.fastq.gz    Forward reads file"
    echo "  read2.fastq.gz    Reverse reads file" 
    echo "  output_dir        Output directory"
    echo ""
    echo "Optional options:"
    echo "  --low-memory      Use low memory mode (MEGAHIT instead of SPAdes)"
    echo "  --skip-pilon      Skip Pilon correction step"
    echo "  --force           Force overwrite of existing output directory"
    echo "  --debug           Enable debug mode"
    echo "  -h, --help        Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 sample_R1.fastq.gz sample_R2.fastq.gz my_assembly"
    echo "  $0 sample_R1.fastq.gz sample_R2.fastq.gz my_assembly --force"
    echo "  $0 sample_R1.fastq.gz sample_R2.fastq.gz my_assembly --low-memory --force --debug"
}

# Parse parameters
READ1=""
READ2=""
OUTPUT=""
LOW_MEMORY=false
SKIP_PILON=false
FORCE=false
DEBUG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        --low-memory)
            LOW_MEMORY=true
            shift
            ;;
        --skip-pilon)
            SKIP_PILON=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        *)
            # Assign required parameters in order
            if [[ -z "$READ1" ]]; then
                READ1="$1"
            elif [[ -z "$READ2" ]]; then
                READ2="$1"
            elif [[ -z "$OUTPUT" ]]; then
                OUTPUT="$1"
            else
                echo "Error: Unknown parameter or too many parameters: $1"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Check required parameters
if [[ -z "$READ1" || -z "$READ2" || -z "$OUTPUT" ]]; then
    echo "Error: Missing required parameters!"
    usage
    exit 1
fi

# Check input files
if [[ ! -f "$READ1" ]]; then
    echo "Error: Forward reads file not found: $READ1"
    exit 1
fi

if [[ ! -f "$READ2" ]]; then
    echo "Error: Reverse reads file not found: $READ2"
    exit 1
fi

# Check if output directory already exists
if [[ -d "$OUTPUT" ]]; then
    if [[ "$FORCE" == false ]]; then
        echo "Warning: Output directory '$OUTPUT' already exists"
        read -p "Continue? Existing files may be overwritten (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Operation cancelled"
            exit 1
        else
            FORCE=true
        fi
    else
        echo "Info: Using --force parameter, will overwrite existing directory"
    fi
fi

# Load configuration
if [[ -f "assembly_config.sh" ]]; then
    source assembly_config.sh
else
    echo "Warning: Configuration file assembly_config.sh not found, using default parameters"
    DEFAULT_THREADS=8
    DEFAULT_MEMORY="8G"
    DEFAULT_PILON_ROUNDS=1
    DEFAULT_QUALITY=20
    DEFAULT_MIN_LENGTH=50
fi

# Build command
CMD="./run_genome_assembly_2.sh \
    -1 \"$READ1\" \
    -2 \"$READ2\" \
    -o \"$OUTPUT\" \
    -t \"$DEFAULT_THREADS\" \
    -m \"$DEFAULT_MEMORY\" \
    -p \"$DEFAULT_PILON_ROUNDS\" \
    -q \"$DEFAULT_QUALITY\" \
    -l \"$DEFAULT_MIN_LENGTH\""

# Add optional parameters
if [[ "$LOW_MEMORY" == true ]]; then
    CMD="$CMD --low-memory"
fi

if [[ "$SKIP_PILON" == true ]]; then
    CMD="$CMD --skip-pilon"
fi

if [[ "$FORCE" == true ]]; then
    CMD="$CMD --force"
fi

if [[ "$DEBUG" == true ]]; then
    CMD="$CMD --debug"
fi

# Display command to be executed
echo "Command to be executed:"
echo "$CMD"
echo

# Confirm execution
read -p "Continue? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Operation cancelled"
    exit 1
fi

# Execute main script
echo "Starting genome assembly analysis..."
echo "=================================="
eval $CMD

# Check execution result
if [[ $? -eq 0 ]]; then
    echo ""
    echo "Analysis completed successfully! Output directory: $OUTPUT"
    echo ""
    echo "Key result files:"
    echo "   - Complete report: $OUTPUT/assembly_report.html"
    echo "   - Assembly results: $OUTPUT/03_assembly/"
    echo "   - Annotation results: $OUTPUT/05_annotation/"
    echo ""
    echo "Next steps:"
    echo "   Open HTML report to view detailed results:"
    echo "   open \"$OUTPUT/assembly_report.html\" || xdg-open \"$OUTPUT/assembly_report.html\""
else
    echo ""
    echo "Error occurred during analysis"
    echo "   Please check log files or rerun with debug mode:"
    echo "   $0 \"$READ1\" \"$READ2\" \"$OUTPUT\" --force --debug"
    exit 1
fi
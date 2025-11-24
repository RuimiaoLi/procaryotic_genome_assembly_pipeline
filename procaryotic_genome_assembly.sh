#!/bin/bash

# Enhanced Prokaryotic Genome Assembly Pipeline Script

set -e  # Exit immediately on error

# Default parameters
THREADS=8
MEMORY="8G"
PILON_ROUNDS=1
QUALITY_THRESHOLD=20
MIN_LENGTH=50
SKIP_PILON=false
LOW_MEMORY_MODE=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Production logging system
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
    # Only log to file if directory exists
    if [[ -d "$OUTPUT_DIR" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$OUTPUT_DIR/analysis.log"
    fi
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    # Only log to file if directory exists
    if [[ -d "$OUTPUT_DIR" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$OUTPUT_DIR/analysis.log"
    fi
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    # Only log to file if directory exists
    if [[ -d "$OUTPUT_DIR" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$OUTPUT_DIR/analysis.log"
    fi
    exit 1
}

info() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
    # Only log to file if directory exists
    if [[ -d "$OUTPUT_DIR" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$OUTPUT_DIR/analysis.log"
    fi
}

# Display help information
usage() {
    echo "Enhanced Prokaryotic Genome Assembly Pipeline"
    echo ""
    echo "Usage: $0 -1 READ1 -2 READ2 -o OUTPUT_DIR [options]"
    echo ""
    echo "Required parameters:"
    echo "  -1, --read1       Forward reads file (fastq.gz)"
    echo "  -2, --read2       Reverse reads file (fastq.gz)" 
    echo "  -o, --output      Output directory"
    echo ""
    echo "Optional parameters:"
    echo "  -t, --threads     Number of threads (default: $THREADS)"
    echo "  -m, --memory      Memory limit (default: $MEMORY)"
    echo "  -p, --pilon-rounds Number of Pilon correction rounds (default: $PILON_ROUNDS)"
    echo "  -q, --quality     Quality threshold (default: $QUALITY_THRESHOLD)"
    echo "  -l, --min-length  Minimum read length (default: $MIN_LENGTH)"
    echo "  --skip-pilon      Skip Pilon correction step"
    echo "  --low-memory      Low memory mode (use MEGAHIT instead of SPAdes)"
    echo "  --force           Force overwrite of existing output directory"
    echo "  --debug           Enable debug mode"
    echo "  -h, --help        Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -1 reads_1.fastq.gz -2 reads_2.fastq.gz -o assembly_output -t 16"
    echo "  $0 -1 reads_1.fastq.gz -2 reads_2.fastq.gz -o assembly_output --low-memory --skip-pilon"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -1|--read1)
            READ1="$2"
            shift 2
            ;;
        -2|--read2) 
            READ2="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -t|--threads)
            THREADS="$2"
            shift 2
            ;;
        -m|--memory)
            MEMORY="$2"
            shift 2
            ;;
        -p|--pilon-rounds)
            PILON_ROUNDS="$2"
            shift 2
            ;;
        -q|--quality)
            QUALITY_THRESHOLD="$2"
            shift 2
            ;;
        -l|--min-length)
            MIN_LENGTH="$2"
            shift 2
            ;;
        --skip-pilon)
            SKIP_PILON=true
            shift
            ;;
        --low-memory)
            LOW_MEMORY_MODE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown parameter: $1"
            ;;
    esac
done

# Check required parameters
if [[ -z "$READ1" || -z "$READ2" || -z "$OUTPUT_DIR" ]]; then
    error "Missing required parameters!"
    usage
    exit 1
fi

# Check input files exist
if [[ ! -f "$READ1" ]]; then
    error "Forward reads file not found: $READ1"
fi

if [[ ! -f "$READ2" ]]; then
    error "Reverse reads file not found: $READ2"
fi

# System resource detection and adjustment
detect_resources() {
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    local available_cores=$(nproc)
    
    info "System detected: ${total_mem_gb}GB RAM, ${available_cores} cores"
    
    # Adjust thread count
    if [[ $THREADS -gt $available_cores ]]; then
        warn "Requested threads ($THREADS) exceeds available cores ($available_cores), adjusting to $available_cores"
        THREADS=$available_cores
    fi
    
    # Adjust memory settings
    if [[ "$MEMORY" =~ ^([0-9]+)G$ ]]; then
        local mem_gb=${BASH_REMATCH[1]}
        if [[ $mem_gb -gt $total_mem_gb ]]; then
            warn "Requested memory ($MEMORY) exceeds system memory (${total_mem_gb}G), adjusting to ${total_mem_gb}G"
            MEMORY="${total_mem_gb}G"
        fi
    fi
    
    # Low memory mode auto-detection
    if [[ $total_mem_gb -lt 8 ]] && [[ $LOW_MEMORY_MODE == false ]]; then
        warn "System memory is limited (${total_mem_gb}GB), consider using --low-memory mode"
    fi
}

# Enhanced version compatibility check
check_tools() {
    local tools=("fastp" "quast" "bwa" "samtools" "seqkit" "prokka")
    
    # Define minimum version requirements
    local min_versions=(
        "fastp:0.20.0"
        "quast:5.0.0"
        "bwa:0.7.0"
        "samtools:1.10"
        "seqkit:2.0.0"
        "prokka:1.14.0"
    )
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "Tool not found: $tool, please ensure it is installed"
        else
            # Version checking
            for version_req in "${min_versions[@]}"; do
                IFS=':' read -r tool_name min_version <<< "$version_req"
                if [[ "$tool" == "$tool_name" ]]; then
                    local current_version
                    case "$tool" in
                        "fastp")
                            current_version=$($tool --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
                            ;;
                        "quast")
                            current_version=$($tool --version 2>/dev/null | grep -oP 'QUAST v\K\d+\.\d+\.\d+' || echo "0.0.0")
                            ;;
                        "bwa")
                            current_version=$($tool 2>&1 | grep -oP 'Version: \K\d+\.\d+\.\d+' || echo "0.0.0")
                            ;;
                        "samtools")
                            current_version=$($tool --version 2>&1 | head -1 | grep -oP '\d+\.\d+' || echo "0.0")
                            ;;
                        "seqkit")
                            current_version=$($tool version 2>/dev/null | grep -oP 'v\K\d+\.\d+\.\d+' || echo "0.0.0")
                            ;;
                        "prokka")
                            current_version=$($tool --version 2>/dev/null | grep -oP 'version \K\d+\.\d+' || echo "0.0")
                            ;;
                        *)
                            current_version="0.0.0"
                            ;;
                    esac
                    
                    # Version comparison
                    if [[ "$(printf '%s\n' "$min_version" "$current_version" | sort -V | head -n1)" != "$min_version" ]]; then
                        warn "$tool version is outdated: current $current_version, required $min_version+"
                    else
                        info "$tool version compatible: $current_version"
                    fi
                    break
                fi
            done
        fi
    done
    
    # Assembly tool version checking
    if [[ $LOW_MEMORY_MODE == true ]]; then
        if ! command -v "megahit" &> /dev/null; then
            error "Low memory mode requires megahit, but it was not found"
        else
            local megahit_version=$(megahit --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
            if [[ "$(printf '%s\n' "1.2.0" "$megahit_version" | sort -V | head -n1)" != "1.2.0" ]]; then
                warn "MEGAHIT version is outdated: current $megahit_version, required 1.2.0+"
            fi
        fi
    else
        if ! command -v "spades.py" &> /dev/null; then
            error "SPAdes (spades.py) not found, please install or use --low-memory mode"
        else
            local spades_version=$(spades.py --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
            if [[ "$(printf '%s\n' "3.15.0" "$spades_version" | sort -V | head -n1)" != "3.15.0" ]]; then
                warn "SPAdes version is outdated: current $spades_version, required 3.15.0+"
            fi
        fi
    fi
    
    if [[ $SKIP_PILON == false ]] && ! command -v "pilon" &> /dev/null; then
        warn "Pilon not found, skipping correction step"
        SKIP_PILON=true
    else
        if [[ $SKIP_PILON == false ]]; then
            local pilon_version=$(pilon --version 2>&1 | grep -oP '\d+\.\d+' || echo "0.0")
            if [[ "$(printf '%s\n' "1.24" "$pilon_version" | sort -V | head -n1)" != "1.24" ]]; then
                warn "Pilon version is outdated: current $pilon_version, required 1.24+"
            fi
        fi
    fi
}

# Disk space monitoring
check_disk_space() {
    local output_path=$(realpath "$OUTPUT_DIR")
    local available_space
    
    # Get available disk space (in KB)
    if command -v df &> /dev/null; then
        available_space=$(df "$output_path" | awk 'NR==2 {print $4}')
    else
        warn "Cannot check disk space, df command not available"
        return 0
    fi
    
    # Estimate required space (5x raw data size + 2GB buffer)
    local read1_size=$(stat -c%s "$READ1" 2>/dev/null || stat -f%z "$READ1")
    local read2_size=$(stat -c%s "$READ2" 2>/dev/null || stat -f%z "$READ2")
    local total_read_size=$((read1_size + read2_size))
    local estimated_needed=$((total_read_size * 5 / 1024 + 2048))  # Convert to KB and add 2GB buffer
    
    info "Disk space check: available ${available_space}KB, estimated required ${estimated_needed}KB"
    
    if [[ $available_space -lt $estimated_needed ]]; then
        local available_gb=$((available_space / 1024 / 1024))
        local needed_gb=$((estimated_needed / 1024 / 1024))
        error "Insufficient disk space! Required at least ${needed_gb}GB, available ${available_gb}GB"
    else
        local safety_buffer=$((available_space * 20 / 100))  # Reserve 20% safety buffer
        local usable_space=$((available_space - safety_buffer))
        
        if [[ $estimated_needed -gt $usable_space ]]; then
            warn "Disk space is limited, consider freeing more space or using --low-memory mode"
        else
            info "Disk space sufficient"
        fi
    fi
}

# Safe execution function
safe_run() {
    local step_name="$1"
    local command="$2"
    local check_file="$3"  # Required output file
    local min_size="$4"    # Minimum file size (optional)
    
    log "Starting: $step_name"
    
    # Record start time
    local start_time=$(date +%s)
    
    # Execute command
    if eval "$command"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "Completed: $step_name (duration: ${duration} seconds)"
        
        # Production environment: validate output file
        if [ -n "$check_file" ]; then
            if [[ -f "$check_file" ]]; then
                local file_size=$(stat -c%s "$check_file" 2>/dev/null || stat -f%z "$check_file")
                if [[ $file_size -eq 0 ]]; then
                    warn "Output file is empty: $check_file"
                elif [ -n "$min_size" ] && [[ $file_size -lt $min_size ]]; then
                    warn "Output file is too small: $check_file (${file_size} bytes)"
                else
                    info "Output validation passed: $check_file (${file_size} bytes)"
                fi
            else
                error "Output file not found: $check_file"
            fi
        fi
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        error "$step_name failed (runtime: ${duration} seconds)"
    fi
}

# Create directory structure
log "Creating output directory structure..."
mkdir -p "$OUTPUT_DIR"/{00_raw_data,01_trimmed,02_quality_control,03_assembly,04_assembly_evaluation,05_annotation}

# Create run status file
echo "Analysis started: $(date)" > "$OUTPUT_DIR/analysis.log"
echo "Input files: $READ1, $READ2" >> "$OUTPUT_DIR/analysis.log"
echo "Output directory: $OUTPUT_DIR" >> "$OUTPUT_DIR/analysis.log"
echo "Parameters: threads=$THREADS, memory=$MEMORY" >> "$OUTPUT_DIR/analysis.log"

# Detect resources and tools
detect_resources
check_disk_space
check_tools

# Prepare raw data
log "Preparing raw data..."
cp "$READ1" "$OUTPUT_DIR/00_raw_data/"
cp "$READ2" "$OUTPUT_DIR/00_raw_data/"
READ1_BASENAME=$(basename "$READ1")
READ2_BASENAME=$(basename "$READ2")

# Step 1: Quality control
safe_run "Quality control" "
fastp \
    -i \"$OUTPUT_DIR/00_raw_data/$READ1_BASENAME\" \
    -I \"$OUTPUT_DIR/00_raw_data/$READ2_BASENAME\" \
    -o \"$OUTPUT_DIR/01_trimmed/trimmed_1.fastq.gz\" \
    -O \"$OUTPUT_DIR/01_trimmed/trimmed_2.fastq.gz\" \
    -q \"$QUALITY_THRESHOLD\" -u 30 -n 5 -l \"$MIN_LENGTH\" \
    --detect_adapter_for_pe \
    --thread \"$THREADS\" \
    --html \"$OUTPUT_DIR/02_quality_control/fastp_report.html\" \
    --json \"$OUTPUT_DIR/02_quality_control/fastp_report.json\"
" "$OUTPUT_DIR/01_trimmed/trimmed_1.fastq.gz" "1000000"

# Step 2: Genome assembly
MEMORY_GB="${MEMORY%G}"
if [[ $LOW_MEMORY_MODE == true ]]; then
    warn "Using low memory mode (MEGAHIT)"
    ASSEMBLY_RESULT="$OUTPUT_DIR/03_assembly/megahit/final.contigs.fa"
    safe_run "Genome assembly (MEGAHIT)" "
    megahit \
        -1 \"$OUTPUT_DIR/01_trimmed/trimmed_1.fastq.gz\" \
        -2 \"$OUTPUT_DIR/01_trimmed/trimmed_2.fastq.gz\" \
        -o \"$OUTPUT_DIR/03_assembly/megahit\" \
        -t \"$THREADS\" \
        --min-contig-len 1000
    " "$ASSEMBLY_RESULT" "10000" 

else
    ASSEMBLY_RESULT="$OUTPUT_DIR/03_assembly/spades/contigs.fasta"
    safe_run "Genome assembly (SPAdes)" "
    spades.py \
        -1 \"$OUTPUT_DIR/01_trimmed/trimmed_1.fastq.gz\" \
        -2 \"$OUTPUT_DIR/01_trimmed/trimmed_2.fastq.gz\" \
        -o \"$OUTPUT_DIR/03_assembly/spades\" \
        -t \"$THREADS\" \
        -m \"$MEMORY_GB\" \
        --careful
    " "$ASSEMBLY_RESULT" "10000"

fi

# Check assembly result
if [[ ! -f "$ASSEMBLY_RESULT" ]]; then
    error "Assembly failed: assembly result file not found $ASSEMBLY_RESULT"
fi

# Step 3: Assembly quality assessment
safe_run "Assembly quality assessment" "
quast \
    \"$ASSEMBLY_RESULT\" \
    -o \"$OUTPUT_DIR/04_assembly_evaluation/quast\" \
    --threads \"$THREADS\" \
    --gene-finding
" "$OUTPUT_DIR/04_assembly_evaluation/quast/report.txt" "1000"

# Step 4: Pilon multi-round correction (optional)
if [[ $SKIP_PILON == false ]]; then
    log "Starting Pilon correction ($PILON_ROUNDS rounds)..."
    
    # Create Pilon-specific directories
    mkdir -p "$OUTPUT_DIR/03_assembly/pilon_align" "$OUTPUT_DIR/03_assembly/pilon_output"
    
    # Clean old Pilon results (if force mode)
    if [[ $FORCE == true ]]; then
        rm -f "$OUTPUT_DIR/03_assembly/pilon_output"/pilon_round*.fasta
        rm -f "$OUTPUT_DIR/03_assembly/pilon_output"/pilon_round*.changes
    fi
    
    # Check disk space for Pilon steps
    local pilon_space_needed=$((total_read_size * 3 / 1024))  # Estimate space for BAM files
    local current_available=$(df "$OUTPUT_DIR" | awk 'NR==2 {print $4}')
    
    if [[ $current_available -lt $pilon_space_needed ]]; then
        warn "Disk space may be insufficient for Pilon correction, consider freeing space or skipping this step"
        read -p "Continue with Pilon correction? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            SKIP_PILON=true
            FINAL_ASSEMBLY="$ASSEMBLY_RESULT"
            log "User chose to skip Pilon correction"
        fi
    fi
    
    for ((round=1; round<=PILON_ROUNDS; round++)); do
        log "Pilon correction round $round/$PILON_ROUNDS..."
        
        if [[ $round -eq 1 ]]; then
            GENOME="$ASSEMBLY_RESULT"
            OUTPUT_PREFIX="pilon_round1"
            ALIGN_PREFIX="aln"
        else
            PREV_ROUND=$((round-1))
            GENOME="$OUTPUT_DIR/03_assembly/pilon_output/pilon_round${PREV_ROUND}.fasta"
            OUTPUT_PREFIX="pilon_round${round}"
            ALIGN_PREFIX="aln${round}"
        fi
        
        # Check if input genome exists
        if [[ ! -f "$GENOME" ]]; then
            warn "Input genome for round $round not found: $GENOME, skipping subsequent corrections"
            break
        fi
        
        # Alignment
        safe_run "Round ${round} read alignment" "
        bwa index \"$GENOME\" && \
        bwa mem -t \"$THREADS\" \"$GENOME\" \
            \"$OUTPUT_DIR/01_trimmed/trimmed_1.fastq.gz\" \
            \"$OUTPUT_DIR/01_trimmed/trimmed_2.fastq.gz\" \
            | samtools view -@ \"$THREADS\" -bS - > \"$OUTPUT_DIR/03_assembly/pilon_align/${ALIGN_PREFIX}.bam\"
        " "$OUTPUT_DIR/03_assembly/pilon_align/${ALIGN_PREFIX}.bam" "1000000"
        
        # Sorting and indexing
        safe_run "Round ${round} BAM file processing" "
        samtools sort -@ \"$THREADS\" \
            -o \"$OUTPUT_DIR/03_assembly/pilon_align/${ALIGN_PREFIX}.sorted.bam\" \
            \"$OUTPUT_DIR/03_assembly/pilon_align/${ALIGN_PREFIX}.bam\" && \
        samtools index \"$OUTPUT_DIR/03_assembly/pilon_align/${ALIGN_PREFIX}.sorted.bam\"
        " "$OUTPUT_DIR/03_assembly/pilon_align/${ALIGN_PREFIX}.sorted.bam" "1000000"
        
        # Calculate coverage
        samtools depth "$OUTPUT_DIR/03_assembly/pilon_align/${ALIGN_PREFIX}.sorted.bam" 2>/dev/null | \
            awk '{sum+=$3; cnt++} END{if(cnt>0) print "Average coverage:",sum/cnt; else print "Coverage calculation failed"}' > \
            "$OUTPUT_DIR/03_assembly/pilon_align/depth_round${round}.txt"
        
        # Pilon correction - using safe memory settings
        PILON_OUTPUT="$OUTPUT_DIR/03_assembly/pilon_output/${OUTPUT_PREFIX}.fasta"
        safe_run "Round ${round} Pilon correction" "
        java -Xmx\"$MEMORY\" -jar \$(dirname \$(which pilon))/../share/pilon-*/pilon.jar \
            --genome \"$GENOME\" \
            --frags \"$OUTPUT_DIR/03_assembly/pilon_align/${ALIGN_PREFIX}.sorted.bam\" \
            --output \"$OUTPUT_PREFIX\" \
            --outdir \"$OUTPUT_DIR/03_assembly/pilon_output\" \
            --threads \"$THREADS\" \
            --changes
        " "$PILON_OUTPUT" "10000"
        
        # Record number of changes
        if [[ -f "$OUTPUT_DIR/03_assembly/pilon_output/${OUTPUT_PREFIX}.changes" ]]; then
            CHANGES=$(wc -l < "$OUTPUT_DIR/03_assembly/pilon_output/${OUTPUT_PREFIX}.changes")
            log "  Round $round correction completed, number of changes: $CHANGES"
            
            # If no changes, end early
            if [[ $CHANGES -eq 0 ]] && [[ $round -ge 2 ]]; then
                log "  No further changes, ending Pilon correction early"
                break
            fi
        else
            warn "Round $round did not generate changes file"
        fi
    done
    
    # Determine final assembly file
    if [[ -f "$OUTPUT_DIR/03_assembly/pilon_output/pilon_round${PILON_ROUNDS}.fasta" ]]; then
        FINAL_ASSEMBLY="$OUTPUT_DIR/03_assembly/pilon_output/pilon_round${PILON_ROUNDS}.fasta"
    else
        # Find latest pilon result
        LATEST_PILON=$(ls "$OUTPUT_DIR/03_assembly/pilon_output"/pilon_round*.fasta 2>/dev/null | tail -n1)
        if [[ -n "$LATEST_PILON" ]]; then
            FINAL_ASSEMBLY="$LATEST_PILON"
            warn "Using latest Pilon result: $LATEST_PILON"
        else
            FINAL_ASSEMBLY="$ASSEMBLY_RESULT"
            warn "No Pilon results found, using original assembly"
        fi
    fi
else
    warn "Skipping Pilon correction step"
    FINAL_ASSEMBLY="$ASSEMBLY_RESULT"
fi

# Step 5: Final quality assessment
safe_run "Final quality assessment" "
mkdir -p \"$OUTPUT_DIR/04_assembly_evaluation/quast_compare\" && \
quast \
    \"$ASSEMBLY_RESULT\" \
    \"$FINAL_ASSEMBLY\" \
    -o \"$OUTPUT_DIR/04_assembly_evaluation/quast_compare\" \
    --threads \"$THREADS\" \
    --labels \"Initial_assembly,Final_assembly\" \
    --gene-finding
"

# Step 6: Genome annotation
RENAMED_GENOME="${FINAL_ASSEMBLY%.*}.renamed.fasta"

# Rename contig IDs
safe_run "Renaming contig IDs" "
seqkit replace -p \"(.+)\" -r \"contig_{nr}\" \"$FINAL_ASSEMBLY\" > \"$RENAMED_GENOME\"
" "$RENAMED_GENOME" "10000"

# Run Prokka
PROKKA_CMD="prokka --outdir \"$OUTPUT_DIR/05_annotation\" \
    --prefix \"annotated_genome\" \
    --cpus \"$THREADS\" \
    --compliant"

[[ $FORCE == true ]] && PROKKA_CMD="$PROKKA_CMD --force"
PROKKA_CMD="$PROKKA_CMD \"$RENAMED_GENOME\""

safe_run "Genome annotation" "$PROKKA_CMD" "$OUTPUT_DIR/05_annotation/annotated_genome.gff" "10000"

# Step 7: Generate final report
log "Step 7: Generating final report..."

# Assembly statistics
safe_run "Generating assembly statistics" "
seqkit stats \"$ASSEMBLY_RESULT\" \"$FINAL_ASSEMBLY\" > \"$OUTPUT_DIR/04_assembly_evaluation/assembly_stats.txt\"
"

# Copy annotation summary
if [[ -f "$OUTPUT_DIR/05_annotation/annotated_genome.txt" ]]; then
    cp "$OUTPUT_DIR/05_annotation/annotated_genome.txt" "$OUTPUT_DIR/04_assembly_evaluation/annotation_summary.txt"
fi

# Create enhanced HTML report
cat > "$OUTPUT_DIR/assembly_report.html" << EOF
<html>
<head>
    <title>Genome Assembly Report - $(date)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }
        h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 25px; }
        .section { margin: 20px 0; padding: 20px; border-left: 4px solid #3498db; background: #f8f9fa; border-radius: 5px; }
        .stats { background: white; padding: 15px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .warning { border-left-color: #f39c12; background: #fef9e7; }
        .success { border-left-color: #27ae60; background: #e8f6f3; }
        a { color: #2980b9; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .file-list { list-style-type: none; padding: 0; }
        .file-list li { padding: 5px 0; border-bottom: 1px solid #ecf0f1; }
    </style>
</head>
<body>
    <h1>Prokaryotic Genome Assembly Analysis Report</h1>
    
    <div class="section success">
        <h2>Analysis Summary</h2>
        <div class="stats">
            <p><strong>Sample Name:</strong> $(basename "$OUTPUT_DIR")</p>
            <p><strong>Analysis Date:</strong> $(date)</p>
            <p><strong>Sequencing Data:</strong> $(basename "$READ1") / $(basename "$READ2")</p>
            <p><strong>Operation Mode:</strong> $([ "$LOW_MEMORY_MODE" = true ] && echo "Low Memory" || echo "Standard") | $([ "$SKIP_PILON" = true ] && echo "Skipped Correction" || echo "Pilon Correction")</p>
        </div>
    </div>
    
    <div class="section">
        <h2>Analysis Pipeline</h2>
        <div class="stats">
            <ol>
                <li>Quality Control (fastp)</li>
                <li>Genome Assembly ($([ "$LOW_MEMORY_MODE" = true ] && echo "MEGAHIT" || echo "SPAdes"))</li>
                <li>Quality Assessment (QUAST)</li>
                <li>Genome Correction ($([ "$SKIP_PILON" = true ] && echo "Skipped" || echo "Pilon"))</li>
                <li>Functional Annotation (Prokka)</li>
            </ol>
        </div>
    </div>
    
    <div class="section">
        <h2>Result Files</h2>
        <div class="stats">
            <ul class="file-list">
                <li><a href="01_trimmed/">Quality-controlled sequencing data</a></li>
                <li><a href="02_quality_control/fastp_report.html">Quality control report</a></li>
                <li><a href="03_assembly/">Assembly results</a></li>
                <li><a href="04_assembly_evaluation/quast/report.html">Assembly quality report</a></li>
                <li><a href="04_assembly_evaluation/quast_compare/report.html">Assembly comparison report</a></li>
                <li><a href="05_annotation/">Genome annotation results</a></li>
            </ul>
        </div>
    </div>
    
    <div class="section">
        <h2>Key Results</h2>
        <div class="stats">
            <ul class="file-list">
                <li><a href="03_assembly/$([ "$LOW_MEMORY_MODE" = true ] && echo "megahit/final.contigs.fa" || echo "spades/contigs.fasta")">Initial assembly result</a></li>
                <li><a href="03_assembly/pilon_output/pilon_round${PILON_ROUNDS}.fasta">Final assembly result</a></li>
                <li><a href="05_annotation/annotated_genome.gff">Genome annotation file (GFF)</a></li>
                <li><a href="05_annotation/annotated_genome.faa">Protein sequence file</a></li>
                <li><a href="04_assembly_evaluation/assembly_stats.txt">Assembly statistics</a></li>
            </ul>
        </div>
    </div>
    
    <div class="section warning">
        <h2>Next Steps</h2>
        <div class="stats">
            <ul>
                <li>Check QUAST report to confirm assembly quality</li>
                <li>Review annotation results to understand gene functions</li>
                <li>Perform comparative genomics analysis (if needed)</li>
                <li>Validate key genes (e.g., resistance genes, virulence factors)</li>
            </ul>
        </div>
    </div>
    
    <footer style="margin-top: 40px; padding: 20px; text-align: center; color: #7f8c8d; border-top: 1px solid #bdc3c7;">
        <p>Generated: $(date) | Script version: Enhanced</p>
    </footer>
</body>
</html>
EOF

# Generate summary report
log "=== Genome Assembly Pipeline Completed ==="
echo ""
echo "Analysis Summary"
echo "================"
echo "Output directory: $OUTPUT_DIR"
echo "Final assembly: $FINAL_ASSEMBLY"
echo "Annotation results: $OUTPUT_DIR/05_annotation/"
echo "Quality assessment: $OUTPUT_DIR/04_assembly_evaluation/"
echo ""
echo "Key Files"
echo "========="
echo "• Complete report: $OUTPUT_DIR/assembly_report.html"
echo "• Assembly statistics: $OUTPUT_DIR/04_assembly_evaluation/assembly_stats.txt"
echo "• Quality control report: $OUTPUT_DIR/02_quality_control/fastp_report.html"
echo "• QUAST report: $OUTPUT_DIR/04_assembly_evaluation/quast/report.html"
echo "• Annotation summary: $OUTPUT_DIR/05_annotation/annotated_genome.txt"
echo ""
echo "Next Steps"
echo "=========="
echo "1. Open HTML report to view complete results"
echo "2. Check QUAST evaluation to confirm assembly quality"
echo "3. Analyze gene functions in annotation results"
echo "4. Perform downstream analysis based on research objectives"

# Display final file size
echo ""
info "Final file size:"
ls -lh "$FINAL_ASSEMBLY" 2>/dev/null || warn "Final assembly file not generated"
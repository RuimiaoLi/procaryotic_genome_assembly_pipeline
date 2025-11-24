#!/bin/bash

# Genome Assembly Configuration File
# Copy this file and modify parameters as needed

# Software paths (specify full path if not in PATH)
FASTP="fastp"
SPADES="spades.py"
MEGAHIT="megahit"
QUAST="quast"
BWA="bwa"
SAMTOOLS="samtools"
PILON="pilon"
PROKKA="prokka"
SEQKIT="seqkit"

# Default parameters
DEFAULT_THREADS=8
DEFAULT_MEMORY="8G"
DEFAULT_PILON_ROUNDS=1
DEFAULT_QUALITY=20
DEFAULT_MIN_LENGTH=50

# Advanced parameters (for advanced users)
SPADES_EXTRA_PARAMS="--careful"
FASTP_EXTRA_PARAMS="--detect_adapter_for_pe -u 30 -n 5"
PROKKA_EXTRA_PARAMS="--compliant --kingdom Bacteria"

# Low memory mode settings
LOW_MEMORY_MEGAHIT_PARAMS="--min-contig-len 1000"
LOW_MEMORY_PROKKA_PARAMS="--mincontiglen 500"

# Debug settings
KEEP_INTERMEDIATES=false
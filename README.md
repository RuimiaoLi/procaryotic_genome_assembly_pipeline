# Prokaryotic Genome Assembly Pipeline

A comprehensive and automated pipeline for prokaryotic genome assembly from Illumina paired-end sequencing data, featuring quality control, assembly, polishing, and annotation.

## Overview

This pipeline provides a robust workflow for assembling prokaryotic genomes from raw sequencing reads to fully annotated genomes. It integrates best practices in genome assembly and offers both standard and low-memory modes to accommodate different computational environments.

## Features

- **Quality Control**: Automated read trimming and quality assessment with FastP
- **Flexible Assembly**: Support for both SPAdes (high-quality) and MEGAHIT (low-memory) assemblers
- **Iterative Polishing**: Multi-round Pilon-based genome improvement
- **Comprehensive Annotation**: Automated functional annotation with Prokka
- **Quality Assessment**: QUAST-based assembly evaluation and comparison
- **Resource Management**: Automatic system resource detection and adjustment
- **Production Ready**: Detailed logging, error handling, and progress tracking

## Quick Start

### Basic Usage

```bash
# Using the simplified runner
./run_assembly.sh sample_R1.fastq.gz sample_R2.fastq.gz output_directory

# Using the main pipeline directly
./run_genome_assembly_2.sh -1 sample_R1.fastq.gz -2 sample_R2.fastq.gz -o output_directory
```

### Advanced Options

```bash
# Low memory mode with MEGAHIT
./run_assembly.sh sample_R1.fastq.gz sample_R2.fastq.gz output_directory --low-memory

# Skip Pilon polishing
./run_assembly.sh sample_R1.fastq.gz sample_R2.fastq.gz output_directory --skip-pilon

# Force overwrite and debug mode
./run_assembly.sh sample_R1.fastq.gz sample_R2.fastq.gz output_directory --force --debug
```

## Installation

### Dependencies

The pipeline requires the following software tools:

| Tool | Use Version | Purpose |
|------|----------------|---------|
| FastP | 1.0.1 | Quality control and adapter trimming |
| SPAdes | 4.0.0 | Genome assembly (standard mode) |
| MEGAHIT | 1.2.9 | Genome assembly (low-memory mode) |
| QUAST | 5.3.0 | Assembly quality assessment |
| BWA | 0.7.18 | Read alignment for polishing |
| SAMtools | 1.19.2 | BAM file processing |
| Pilon | 1.24 | Genome polishing |
| Prokka | 1.14.6 | Genome annotation |
| SeqKit | 2.10.1 | Sequence manipulation |

### Installation Methods

#### 1. Conda Environment (Recommended)

```bash
# Create and activate environment
conda create -n genome_assembly -c bioconda -c conda-forge \
    fastp spades megahit quast bwa samtools pilon prokka seqkit
conda activate genome_assembly
```

#### 2. Manual Installation

Install each tool following their respective documentation:
- [SPAdes](https://github.com/ablab/spades)
- [MEGAHIT](https://github.com/voutcn/megahit)
- [Prokka](https://github.com/tseemann/prokka)
- [QUAST](http://bioinf.spbau.ru/quast)
- [FastP](https://github.com/OpenGene/fastp)
- [Pilon](https://github.com/broadinstitute/pilon)

## Configuration

### Configuration File

Create or modify `assembly_config.sh` to customize pipeline parameters:

```bash
# Default parameters
DEFAULT_THREADS=8
DEFAULT_MEMORY="8G"
DEFAULT_PILON_ROUNDS=1
DEFAULT_QUALITY=20
DEFAULT_MIN_LENGTH=50

# Software paths (specify full path if not in PATH)
FASTP="fastp"
SPADES="spades.py"
MEGAHIT="megahit"
# ... other tools
```

### Resource Requirements

| Mode | Minimum RAM | Recommended RAM | Storage |
|------|-------------|-----------------|---------|
| Standard (SPAdes) | 8 GB | 16+ GB | 10-20 GB |
| Low Memory (MEGAHIT) | 4 GB | 8 GB | 5-10 GB |

## Pipeline Workflow

1. **Quality Control**
   - Adapter trimming and quality filtering with FastP
   - Generate quality assessment reports

2. **Genome Assembly**
   - SPAdes: High-quality assembly with careful mode
   - MEGAHIT: Memory-efficient assembly for large datasets

3. **Assembly Evaluation**
   - QUAST analysis of assembly metrics
   - Contig statistics and quality assessment

4. **Genome Polishing** (Optional)
   - Multi-round Pilon correction
   - Read mapping with BWA
   - Iterative improvement with change tracking

5. **Functional Annotation**
   - Prokka annotation with standardized outputs
   - Gene calling, tRNA, rRNA identification
   - Functional assignment

6. **Final Reporting**
   - Comprehensive HTML report
   - Assembly statistics and comparison
   - Quality metrics and next steps

## Output Structure

```
output_directory/
├── 00_raw_data/           # Copy of input reads
├── 01_trimmed/            # Quality-controlled reads
├── 02_quality_control/    # FastP reports
├── 03_assembly/           # Assembly results
│   ├── spades/            # SPAdes assembly outputs
│   ├── megahit/           # MEGAHIT assembly outputs
│   └── pilon_output/      # Polished assemblies
├── 04_assembly_evaluation/ # QUAST reports and statistics
├── 05_annotation/         # Prokka annotation results
├── assembly_report.html   # Comprehensive HTML report
└── analysis.log          # Pipeline execution log
```

## Key Output Files

- **Assembly Results**: `03_assembly/[spades|megahit]/contigs.fasta`
- **Polished Assembly**: `03_assembly/pilon_output/pilon_round*.fasta`
- **Annotation Files**: 
  - `05_annotation/annotated_genome.gff` (GFF3 annotation)
  - `05_annotation/annotated_genome.faa` (Protein sequences)
  - `05_annotation/annotated_genome.fna` (Nucleotide sequences)
- **Quality Reports**: 
  - `04_assembly_evaluation/quast/report.html` (QUAST report)
  - `02_quality_control/fastp_report.html` (Quality control)

## Usage Examples

### Standard Assembly with Polishing

```bash
./run_assembly.sh \
    SRR1234567_1.fastq.gz \
    SRR1234567_2.fastq.gz \
    ecoli_assembly \
    -t 16 \
    -m 32G \
    -p 2
```

### Low-Memory Assembly without Polishing

```bash
./run_assembly.sh \
    large_dataset_1.fastq.gz \
    large_dataset_2.fastq.gz \
    large_assembly \
    --low-memory \
    --skip-pilon \
    -t 8 \
    -m 8G
```

## Troubleshooting

### Common Issues

1. **Memory Errors**: Use `--low-memory` mode or increase available RAM
2. **Disk Space**: Ensure 10-20GB free space for temporary files
3. **Version Compatibility**: Check tool versions meet minimum requirements
4. **Permission Denied**: Ensure scripts are executable: `chmod +x *.sh`

### Debug Mode

Enable debug output for troubleshooting:

```bash
./run_assembly.sh reads_1.fq reads_2.fq output --debug
```

## Citation

If you use this pipeline in your research, please cite the respective tools:

- SPAdes: Bankevich et al., 2012, J. Comput. Biol.
- MEGAHIT: Li et al., 2015, Bioinformatics  
- Prokka: Seemann, 2014, Bioinformatics
- QUAST: Gurevich et al., 2013, Bioinformatics
- FastP: Chen et al., 2018, Bioinformatics
- Pilon: Walker et al., 2014, PLoS ONE

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review the analysis log in your output directory
3. Ensure all dependencies are properly installed
4. Verify input file formats and quality

## License

This pipeline is provided under the MIT License. See LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.
```

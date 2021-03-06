#!/bin/bash

NUMCPUS=12

set -e

THISDIR=$(dirname $0)

export PATH="$THISDIR/../scripts:$PATH"
# In case RAxML has to be downloaded, it will be here
export PATH="$PATH:$THISDIR/standard-RAxML-8.1.16"

# Print a message to stderr with the script name
function msg(){
  echo "$(basename $0): $@" >&2
}

msg "Looking for dependencies for both Gen-FS Gopher and for CFSAN SNP Pipeline"
for exe in esearch fastq-dump perl make GenFSGopher.pl run_snp_pipeline.sh \
  bowtie2 tabix bgzip bcftools; do
  which $exe
done
# Need perl >= 5.12.0
msg "Testing if perl >= 5.12.0 is in PATH"
perl -e 'use 5.12.0; print "  -OK\n"'
msg "Checking for samtools v1 or above"
VERSION=$(samtools --version | grep samtools | grep -P -o '\d+(.\d+)?')
VERSION=${VERSION:0:1}
if (( $(echo "$VERSION < 1" | bc -l) )); then
  msg "Found version $VERSION of samtools but need >= 1"
  exit 1
fi
msg "  -OK"

msg "Testing for RAxML, but if it's not present, I will download and install it"
which raxmlHPC || ( \
  wget 'https://github.com/stamatak/standard-RAxML/archive/v8.1.16.tar.gz' -O $THISDIR/raxml_v8.1.16.tar.gz && \
  cd $THISDIR && tar zxvf raxml_v8.1.16.tar.gz && \
  make -j $NUMCPUS -C standard-RAxML-8.1.16 -f Makefile.gcc && \
  cd - && \
  rm -vf $THISDIR/raxml_v8.1.16.tar.gz
) && \
which raxmlHPC

msg "Downloading datasets"
for tsv in $THISDIR/../datasets/*.tsv; do
  name=$(basename $tsv .tsv)

  msg "Downloading $name"
  GenFSGopher.pl --outdir $THISDIR/$name --layout cfsan --numcpus $NUMCPUS $tsv 

  msg "SNP-Pipeline"

  REF=$(ls $THISDIR/$name/reference/*.fasta | head -n 1)
  nice run_snp_pipeline.sh -s $THISDIR/$name/samples -m soft -o $THISDIR/$name/snp-pipeline $REF

  # Infer a phylogeny following SNP-Pipeline
  cd $THISDIR/$name/snp-pipeline
    rm -vf RAxML*.snp-pipeline # rm any previous results
    raxmlHPC -f a -s snpma.fasta -x $RANDOM -p $RANDOM -N 100 -m GTRGAMMA -n snp-pipeline
  cd -
  NEWTREE=$THISDIR/$name/snp-pipeline/RAxML_bipartitions.snp-pipeline
  REFTREE=$THISDIR/$name/tree.dnd

  # Compare vs original tree

  # Fix any isolate that has quotes or spaces
  cat $REFTREE $NEWTREE | perl -lane "s/ /_/g; s/'//g; print;" > $THISDIR/$name/allTrees.dnd
  # Compare with RAxML
  cd $THISDIR/$name
    rm -vf RAxML*.TEST # rm any previous results
    raxmlHPC -m GTRCAT -z allTrees.dnd -f r -n TEST
    cat RAxML_RF-Distances.TEST
    # Robinson-Foulds metric is the third number in this file
    RF=$(cut -f 3 -d ' ' RAxML_RF-Distances.TEST)
  cd -

  msg "Robinson-Foulds metric is $RF between your tree and the reference tree"

done





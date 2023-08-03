process HICPRO2PAIRS {
    tag "$meta.id"
    label 'process_medium'

    conda (params.enable_conda ? "bioconda::pairix=0.3.7" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pairix:0.3.7--py36h30a8e3e_3' :
        'quay.io/biocontainers/pairix:0.3.7--py36h30a8e3e_3' }"

    input:
    tuple val(meta), path(vpairs)
    path chrsize

    output:
    tuple val(meta), path("*.pairs.gz"), path("*.pairs.gz.px2"), emit: pairs
    path("versions.yml"), emit: versions

    script:
    prefix = "${meta.id}"
    """
    ##columns: readID chr1 pos1 chr2 pos2 strand1 strand2
    awk '{OFS="\t";print \$1,\$2,\$3,\$5,\$6,\$4,\$7}' $vpairs > ${prefix}_contacts.pairs
    awk '{file=$2 ".chunk"}{print > file}' ${prefix}_contacts.pairs
    for X in *.chunk; do sort -k2,2 -k4,4 -k3,3n -k5,5n < $X > sorted-$X; done
    ls sorted-*.chunk | sort  -V | xargs cat > ${prefix}_contacts.pairs.tmp
    bgzip -c -@ 4  ${prefix}_contacts.pairs.tmp > ${prefix}_contacts.pairs.gz
    pairix -f ${prefix}_contacts.pairs.gz
    rm *chunk
    rm ${prefix}_contacts.pairs.tmp

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pairix: \$(echo \$(pairix 2>&1 | grep Version | sed -e 's/Version: //')
    END_VERSIONS
    """
}

/*
 * mustache call loops
 */

process MUSTACHE_CALL_LOOPS {
    label 'process_medium'

    conda (params.enable_conda ? "conda-forge::mustache-hic==1.2.7" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://stanfordmedicine.box.com/shared/static/16nwhgetqb84y5p1h2uyd0zu4fs2xerf.sif' :
        '' }"

    input:
    tuple val(meta), path(mcool)

    output:
    path("*mustacheLoops*"), emit:results
    path("versions.yml"), emit:versions

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mustache -f ${mcool} \
        -o ${prefix}_mustacheLoops_res_${meta.resolution} \
        ${args} \
        -p ${task.cpus} \
		-r ${meta.resolution}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mustache-hic: 1.2.7)
    END_VERSIONS
    """
}

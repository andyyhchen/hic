/*
 * Cooltools - call dots
 */

process COOLTOOLS_CALL_LOOPS {
    label 'process_medium'
	label 'error_ignore'

    conda (params.enable_conda ? "bioconda::cooltools=0.5.1" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/cooltools:0.5.1--py37h37892f8_0' :
        'quay.io/biocontainers/cooltools:0.5.1--py37h37892f8_0' }"

    input:
    tuple val(meta), path(cool)

    output:
    path("*cooltoolsLoops*"), emit:results
    path("versions.yml"), emit:versions

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
	
	cooltools expected-cis -p ${task.cpus} -o ${prefix}_expected_${meta.resolution}.tsv ${cool}
	
	cooltools dots --fdr 0.05 -p ${task.cpus} -o ${prefix}_cooltoolsLoops_res_${meta.resolution}.tsv ${cool} ${prefix}_expected_${meta.resolution}.tsv::balanced.avg 

	rm ${prefix}_expected_${meta.resolution}.tsv


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cooltools: \$(cooltools --version 2>&1 | sed 's/cooltools, version //')
    END_VERSIONS
    """
}

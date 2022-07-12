process GET_JUICEBOX{
  label 'process_medium'

  conda (params.enable_conda ? "conda-forge::python=3.9" : null)
  container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
      'https://stanfordmedicine.box.com/shared/static/33l6xccoygd84frln2qrabnsck0ekn6w.img' :
      'rnakato/juicer'}"

  input:
  tuple val(meta), path(vpairs)
  path chrsize

  output:
  tuple val(meta), path("*.hic"), emit: boxes

  script:
  """
  hicpro2juicebox.sh \\
    -g ${chrsize} \\
    -i ${vpairs} \\
    -j /opt/juicer/scripts/common/juicer_tools.jar
  """
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Validate input parameters
WorkflowHic.initialise(params, log)

// Check input path parameters to see if they exist
def checkPathParamList = [ params.input ]
checkPathParamList = [
    params.input, params.multiqc_config,
    params.fasta, params.bwt2_index
]

for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
if (params.input) { ch_input = file(params.input) } else { exit 1, 'Input samplesheet not specified!' }

//*****************************************
// Digestion parameters
if (params.digestion){
  restriction_site = params.digestion ? params.digest[ params.digestion ].restriction_site ?: false : false
  ch_restriction_site = Channel.value(restriction_site)
  ligation_site = params.digestion ? params.digest[ params.digestion ].ligation_site ?: false : false
  ch_ligation_site = Channel.value(ligation_site)
}else if (params.dnase){
  ch_restriction_site = Channel.empty()
  ch_ligation_site = Channel.empty()
}else{
   exit 1, "Ligation motif not found. Please either use the `--digestion` parameters or specify the `--restriction_site` and `--ligation_site`. For DNase Hi-C, please use '--dnase' option"
}

//****************************************
// Maps resolution for downstream analysis

ch_map_res = Channel.from( params.bin_size ).splitCsv().flatten()
if (params.res_tads && !params.skip_tads){
  Channel.from( "${params.res_tads}" )
    .splitCsv()
    .flatten()
    .set {ch_tads_res}
  ch_map_res = ch_map_res.concat(ch_tads_res)
}else{
  ch_tads_res=Channel.empty()
  if (!params.skip_tads){
    log.warn "[nf-core/hic] Hi-C resolution for TADs calling not specified. See --res_tads" 
  }
}

if (params.res_loops && !params.skip_loops){
  Channel.from( "${params.res_loops}" )
    .splitCsv()
    .flatten()
    .set {ch_loops_res}
  ch_map_res = ch_map_res.concat(ch_loops_res)
}else{
  ch_loops_res=Channel.empty()
  if (!params.skip_loops){
    log.warn "[nf-core/hic] Hi-C resolution for LOOPs calling not specified. See --res_loops" 
  }
}

if (params.res_dist_decay && !params.skip_dist_decay){
  Channel.from( "${params.res_dist_decay}" )
    .splitCsv()
    .flatten()
    .set {ch_ddecay_res}
   ch_map_res = ch_map_res.concat(ch_ddecay_res)
}else{
  ch_ddecay_res = Channel.empty()
  if (!params.skip_dist_decay){
    log.warn "[nf-core/hic] Hi-C resolution for distance decay not specified. See --res_dist_decay" 
  }
}

if (params.res_compartments && !params.skip_compartments){
  Channel.from( "${params.res_compartments}" )
    .splitCsv()
    .flatten()
    .set {ch_comp_res}
   ch_map_res = ch_map_res.concat(ch_comp_res)
}else{
  ch_comp_res = Channel.empty()
  if (!params.skip_compartments){
    log.warn "[nf-core/hic] Hi-C resolution for compartment calling not specified. See --res_compartments" 
  }
}

ch_map_res = ch_map_res.unique()
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CONFIG FILES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

ch_multiqc_config        = file("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
ch_multiqc_custom_config = params.multiqc_config ? Channel.fromPath(params.multiqc_config) : Channel.empty()

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Local to the pipeline
//
include { HIC_PLOT_DIST_VS_COUNTS } from '../modules/local/hicexplorer/hicPlotDistVsCounts' 
include { MULTIQC } from '../modules/local/multiqc'

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { INPUT_CHECK } from '../subworkflows/local/input_check'
include { PREPARE_GENOME } from '../subworkflows/local/prepare_genome'
include { HICPRO } from '../subworkflows/local/hicpro'
include { COOLER } from '../subworkflows/local/cooler'
include { COMPARTMENTS } from '../subworkflows/local/compartments'
include { TADS } from '../subworkflows/local/tads'
include { LOOPS } from '../subworkflows/local/loops'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//

include { CUSTOM_DUMPSOFTWAREVERSIONS } from '../modules/nf-core/modules/custom/dumpsoftwareversions/main'
include { FASTQC  } from '../modules/nf-core/modules/fastqc/main'
//include { MULTIQC } from '../modules/nf-core/modules/multiqc/main'


// FUNCTIONS
//add resolution in meta

def addResolution(row) {
  def meta = [:]
  meta.id = row[0].id
  meta.resolution = row[2]
  return [meta, row[1], row[2]]
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  CHANNELS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

Channel.fromPath( params.fasta )
       .ifEmpty { exit 1, "Genome index: Fasta file not found: ${params.fasta}" }
       .set { ch_fasta }

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Info required for completion email and summary
def multiqc_report = []

workflow HIC {

  ch_versions = Channel.empty()

  //
  // SUBWORKFLOW: Read in samplesheet, validate and stage input files
  //
  INPUT_CHECK (
    ch_input
  )

  //INPUT_CHECK.out.reads.view()

  //
  // SUBWORKFLOW: Prepare genome annotation
  //
  PREPARE_GENOME(
    ch_fasta,
    ch_restriction_site
  )
  ch_versions = ch_versions.mix(PREPARE_GENOME.out.versions)

  //
  // MODULE: Run FastQC
  //
  FASTQC (
    INPUT_CHECK.out.reads
  )
  ch_versions = ch_versions.mix(FASTQC.out.versions)

  //
  // SUB-WORFLOW: HiC-Pro
  //
  HICPRO (
    INPUT_CHECK.out.reads,
    PREPARE_GENOME.out.index,
    PREPARE_GENOME.out.res_frag,
    PREPARE_GENOME.out.chromosome_size,
    ch_ligation_site,
    ch_map_res
  )
  ch_versions = ch_versions.mix(HICPRO.out.versions)

  //
  // SUB-WORKFLOW: COOLER
  //
  COOLER (
    HICPRO.out.pairs,
    PREPARE_GENOME.out.chromosome_size,
    ch_map_res
  )
  ch_versions = ch_versions.mix(COOLER.out.versions)

  //
  // MODULE: HICEXPLORER/HIC_PLOT_DIST_VS_COUNTS
  //
  if (!params.skip_dist_decay){
    COOLER.out.cool
      .combine(ch_ddecay_res)
      .filter{ it[0].resolution == it[2] }
      .map { it -> [it[0], it[1]]}
      .set{ ch_distdecay }

    HIC_PLOT_DIST_VS_COUNTS(
      ch_distdecay
    )
    ch_versions = ch_versions.mix(HIC_PLOT_DIST_VS_COUNTS.out.versions)
  }

  //
  // SUB-WORKFLOW: COMPARTMENT CALLING
  //
  if (!params.skip_compartments){
    COOLER.out.cool
      .combine(ch_comp_res)
      .filter{ it[0].resolution == it[2] }
      .map { it -> [it[0], it[1], it[2]]}
      .set{ ch_cool_compartments }

    COMPARTMENTS (
      ch_cool_compartments,
      ch_fasta,
      PREPARE_GENOME.out.chromosome_size
    )
    ch_versions = ch_versions.mix(COMPARTMENTS.out.versions)
  }

  //
  // SUB-WORKFLOW : TADS CALLING
  //
  if (!params.skip_tads){
    COOLER.out.cool
      .combine(ch_tads_res)
      .filter{ it[0].resolution == it[2] }
      .map { it -> [it[0], it[1]]}
      .set{ ch_cool_tads }
                                                                                                                                                                                                            
    TADS(
      ch_cool_tads
    )
    ch_versions = ch_versions.mix(TADS.out.versions)
  }

  //
  // SUB-WORKFLOW : LOOP CALLING
  //
  
  if (!params.skip_loops){
    COOLER.out.cool
		.combine(ch_loops_res)
		.filter{ it[0].resolution == it[2] }
		.map {it -> [it[0], it[1]]}
		.set { ch_cool_loops }

	
	LOOPS(
	  ch_cool_loops
	)
	ch_versions = ch_versions.mix(LOOPS.out.versions)
	
  }
  
  
  //
  // SOFTWARE VERSION
  //
  CUSTOM_DUMPSOFTWAREVERSIONS(
    ch_versions.unique().collectFile(name: 'collated_versions.yml')
  )

  //
  // MODULE: MultiQC
  //
  workflow_summary    = WorkflowHic.paramsSummaryMultiqc(workflow, summary_params)
  ch_workflow_summary = Channel.value(workflow_summary)

  ch_multiqc_files = Channel.empty()
  ch_multiqc_files = ch_multiqc_files.mix(Channel.from(ch_multiqc_config))
  ch_multiqc_files = ch_multiqc_files.mix(Channel.from(ch_multiqc_custom_config.collect().ifEmpty([])))
  ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
  ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.map{it->it[1]})
  ch_multiqc_files = ch_multiqc_files.mix(HICPRO.out.mqc)

  MULTIQC (
    ch_multiqc_config,
    ch_multiqc_custom_config.collect().ifEmpty([]),
    ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'),
    FASTQC.out.zip.map{it->it[1]},
    HICPRO.out.mqc.collect()
  )
  multiqc_report = MULTIQC.out.report.toList()
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    COMPLETION EMAIL AND SUMMARY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
  if (params.email || params.email_on_fail) {
      NfcoreTemplate.email(workflow, params, summary_params, projectDir, log, multiqc_report)
  }
  NfcoreTemplate.summary(workflow, params, log)
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

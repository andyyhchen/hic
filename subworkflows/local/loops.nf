include { MUSTACHE_CALL_LOOPS } from '../../modules/local/mustache/mustacheCallLoops'
include { COOLTOOLS_CALL_LOOPS } from '../../modules/local/cooltools/dots'

workflow LOOPS {

  take:
  cool

  main:
  ch_versions = Channel.empty()
  ch_loops = Channel.empty()

  
  if (params.loops_caller =~ 'mustache'){
    MUSTACHE_CALL_LOOPS(cool)
    ch_versions = ch_versions.mix(MUSTACHE_CALL_LOOPS.out.versions)
    ch_loops = ch_loops.mix(MUSTACHE_CALL_LOOPS.out.results)
  }
  
  if (params.loops_caller =~ 'cooltools'){
    COOLTOOLS_CALL_LOOPS(cool)
    ch_versions = ch_versions.mix(COOLTOOLS_CALL_LOOPS.out.versions)
    ch_loops = ch_loops.mix(COOLTOOLS_CALL_LOOPS.out.results)
  }
  
  
  emit:
  loops = ch_loops
  versions = ch_versions
}
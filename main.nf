#!/usr/bin/env nextflow
nextflow.enable.dsl=2
import sun.nio.fs.UnixPath

params.template = "$baseDir/resources/report.Rmd"
params.css = "$baseDir/resources/style.css"

def get_run_id(UnixPath path) {
    path.subpath(6,7)
}

process RenderReport {
    tag {run_id}
    cache 'deep'
    stageInMode 'copy'
    module 'mugqic/pandoc'
    executor 'local'

    input:
    tuple val(run_id), path(jsons), path(sample_sheet), path("demux_metrics/*"), path(template), path(css)

    output:
    tuple val(run_id), path("${run_id}.report.html")

    """
    #!/usr/bin/env Rscript
    library(rmarkdown)
    render("$template", \
      output_format="html_document", \
      clean=FALSE,
      output_file="${run_id}.report.html", \
      output_dir=getwd(), \
      knit_root_dir=getwd(), \
      params=list( \
          version = "$workflow.manifest.version", \
          commitid = "$workflow.commitId" \
      ) \
    )
    """
}

process UploadRunReport {
    tag {run_id}
    executor 'local'

    input:
    tuple val(run_id), path(report)

    """
    sftp -P 22004 sftp_p25@sftp-arbutus.genap.ca <<EOF
    put $report /datahub297/MGI_validation/2021/
    chmod 664 /datahub297/MGI_validation/2021/*.html
    EOF
    """
}



process UploadRunReportTest {
    tag {run_id}
    executor 'local'

    input:
    tuple val(run_id), path(report)

    output:
    tuple val(run_id), val("https://datahub-297-p25.p.genap.ca/MGI_validation/testing/$report")

    """
    sftp -P 22004 sftp_p25@sftp-arbutus.genap.ca <<EOF
    mkdir /datahub297/MGI_validation/testing/
    put $report /datahub297/MGI_validation/testing/
    chmod 664 /datahub297/MGI_validation/testing/*.html
    EOF
    """
}

workflow {
    sample_sheets =  Channel.fromPath("/lb/robot/research/processing/dnbseqg400/*/*/*_samples.txt") \
    | map( it -> [get_run_id(it), it] )

    run_validations = Channel.fromPath("/lb/robot/research/processing/dnbseqg400/*/*/*/*.run_validation_report.json") \
    | map( it -> [get_run_id(it), it] )

    demux_metrics = Channel.fromPath("/lb/robot/research/processing/dnbseqg400/*/*/*/*.DemuxFastqs.metrics.txt") \
    | map ( it -> [get_run_id(it), it] ) \
    | groupTuple()

    rmd_template = file(params.template)
    rmd_css = file(params.css)

    run_validations \
    | groupTuple() \
    | combine(sample_sheets, by: 0) \
    | combine(demux_metrics, by: 0) \
    | combine([[rmd_template, rmd_css]]) \
    | RenderReport \
    | UploadRunReport
}

workflow test {
    run_validations = Channel.fromPath("/lb/robot/research/processing/dnbseqg400/*/*/*/*.run_validation_report.json") \
    | map( it -> [get_run_id(it), it] )

    sample_sheets =  Channel.fromPath("/lb/robot/research/processing/dnbseqg400/*/*/*_samples.txt") \
    | map( it -> [get_run_id(it), it] )

    demux_metrics = Channel.fromPath("/lb/robot/research/processing/dnbseqg400/*/*/*/*.DemuxFastqs.metrics.txt") \
    | map ( it -> [get_run_id(it), it] ) \
    | groupTuple()

    rmd_template = file(params.template)
    rmd_css = file(params.css)

    run_validations \
    | groupTuple() \
    | combine(sample_sheets, by: 0) \
    | combine(demux_metrics, by: 0) \
    | combine([[rmd_template, rmd_css]]) \
    | take(5) \
    | RenderReport \
    | UploadRunReportTest \
    | view { run_id, url -> "Run $run_id: $url" }
}
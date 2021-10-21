#!/usr/bin/env nextflow
nextflow.enable.dsl=2
import sun.nio.fs.UnixPath

params.template = "$baseDir/resources/report.Rmd"
params.css = "$baseDir/resources/style.css"

def get_run_id(UnixPath path) {
    path.subpath(6,7)
}

process GetInputs {
    tag "$run_id"
    executor 'local'

    input:
    tuple val(run_id), path(rundir)

    output:
    tuple val(run_id), path(out)

    """
    mkdir out
    cp ${rundir}/*.txt out/
    for json in \$(find ${rundir}/ -name '*run_validation_report.json'); do cp \$json out; done
    for metrics in \$(find ${rundir}/ -name '*DemuxFastqs.metrics.txt'); do cp \$metrics out; done
    """
}

process RenderReport {
    tag {run_id}
    cache 'deep'
    module 'mugqic/pandoc'
    executor 'local'

    input:
    tuple val(run_id), path("inputs"), path(template), path(css)

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
    rmd_template = file(params.template)
    rmd_css = file(params.css)

    // run_dirs = Channel.fromPath("/lb/robot/research/MGISeq/dnbseqg400/*/*/*_samples.txt") \
    run_dirs = Channel.fromPath("/lb/robot/research/MGISeq/dnbseqg400/2021/210908_R2130400190018_10092_AV300085352_10092MG02A-dnbseqg400/92-1776580_24-285681_samples.txt") \
    | map { [get_run_id(it), it.getParent()] }

    run_dirs \
    | GetInputs \
    | combine([[rmd_template, rmd_css]]) \
    | RenderReport \
    | view()

    // run_validations \
    // | combine(sample_sheets, by: 0) \
    // | combine(demux_metrics, by: 0) \
    // | combine([[rmd_template, rmd_css]]) \
    // | RenderReport \
    // | view()
    // | UploadRunReport
}

workflow test {
    sample_sheets =  Channel.fromPath("/lb/robot/research/processing/dnbseqg400/*/*/*_samples.txt") \
    | map( it -> [get_run_id(it), it] )

    run_validations = Channel.fromPath("/lb/robot/research/processing/dnbseqg400/*/*/*/*.run_validation_report.json") \
    | map( it -> [get_run_id(it), it] ) \
    | groupTuple()

    demux_metrics = Channel.fromPath("/lb/robot/research/processing/dnbseqg400/*/*/*/*.DemuxFastqs.metrics.txt") \
    | map ( it -> [get_run_id(it), it] ) \
    | groupTuple()

    rmd_template = file(params.template)
    rmd_css = file(params.css)

    run_validations \
    | combine(sample_sheets, by: 0) \
    | combine(demux_metrics, by: 0) \
    | combine([[rmd_template, rmd_css]]) \
    | take(5) \
    | RenderReport \
    | UploadRunReportTest \
    | view { run_id, url -> "Run $run_id: $url" }
}
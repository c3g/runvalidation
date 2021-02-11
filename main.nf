#!/usr/bin/env nextflow
nextflow.enable.dsl=2
import sun.nio.fs.UnixPath

params.template = "$baseDir/resources/report.Rmd"
params.css = "$baseDir/resources/style.css"

def get_run_id(UnixPath path) {
    path.subpath(6,7)
}

def get_lane(UnixPath path) {
    path.subpath(7,8)
}

process RenderReport {
    tag {run_id}
    cache 'deep'
    stageInMode 'copy'
    module 'mugqic_dev/pandoc'
    executor 'local'

    input:
    tuple val(run_id), path(jsons), path(sample_sheet), path(template), path(css)

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
      knit_root_dir=getwd() \
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

workflow {
    sample_sheets =  Channel.fromPath("/lb/robot/research/MGISeq/dnbseqg400/*/*/*_samples.txt") \
    | map( it -> [it.subpath(6,7), it] )

    run_validations = Channel.fromPath("/lb/robot/research/MGISeq/dnbseqg400/*/*/*/*.run_validation_report.json") \
    | map( it -> [get_run_id(it), it] )

    rmd_template = file(params.template)
    rmd_css = file(params.css)





    run_validations \
    | groupTuple() \
    | combine(sample_sheets, by: 0) \
    | combine([[rmd_template, rmd_css]]) \
    | RenderReport \
    | UploadRunReport
}
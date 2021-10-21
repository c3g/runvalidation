#!/usr/bin/env nextflow
nextflow.enable.dsl=2

import sun.nio.fs.UnixPath

params.template = "$baseDir/resources/report.Rmd"
params.css = "$baseDir/resources/style.css"
params.eventfiles = "/lb/robot/research/MGISeq/dnbseqg400/*/*/*.txt"

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
    for stats in \$(find ${rundir}/ -name '*.fqStat.txt'); do cp \$stats out; done
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

workflow {
    rmd_template = file(params.template)
    rmd_css = file(params.css)

    run_dirs = Channel.fromPath(params.eventfiles) \
    | map { [get_run_id(it), it.getParent()] }

    run_dirs \
    | GetInputs \
    | combine([[rmd_template, rmd_css]]) \
    | RenderReport \
    | UploadRunReport
}
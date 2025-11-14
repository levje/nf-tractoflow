process STATS_JSONTOCSV {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
    tuple val(meta), path(stats_json)

    output:
    tuple val(meta), path("*_stats.json")   , emit: stats_json
    tuple val(meta), path("*_stats.csv")    , emit: stats_csv
    path "versions.yml"                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Clean the CSV by removing prefixes/suffixes from the bundle names
    jq '
        with_entries(
            .key |= (
            sub("${prefix}_"; "") |
            sub("_mask"; "") |
            sub("_warped"; "")
            )
            # Also update keys of the nested object
            | .value |= (
                with_entries(
                    .key |= (
                    sub("${prefix}__"; "") |
                    sub("${prefix}_"; "") |
                    sub("_warped"; "")
                    )
                )
            )
        )
        ' ${stats_json} > ${prefix}_stats.json

    # Convert the cleaned JSON to CSV
    bundles=\$(jq -r "keys[]" ${prefix}_stats.json)

    # Need the first bundle name to extract the metrics names from it
    first_bundle=\$(printf '%s\\n' \$bundles | head -n 1)

    # Extract the metrics names from this first bundle
    metrics=\$(FIRST_BUNDLE="\$first_bundle" jq -r ".\\"\$first_bundle\\" | keys[]" ${prefix}_stats.json)

    # Output the CSV file

    echo "sid,bundle,metric,mean,std" > ${prefix}_stats.csv
    for bundle in \$bundles;
    do
        for metric in \$metrics;
        do
            mean=\$(jq -r --arg BUNDLE "\$bundle" --arg METRIC "\$metric" '.[\$BUNDLE].[\$METRIC].mean' ${prefix}_stats.json)
            std=\$(jq -r --arg BUNDLE "\$bundle" --arg METRIC "\$metric" '.[\$BUNDLE].[\$METRIC].std' ${prefix}_stats.json)

            line="${prefix},\${bundle},\${metric},\${mean},\${std}"
            echo \$line >> ${prefix}_stats.csv
        done
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        jq: \$(jq --version |& sed '1!d ; s/jq-//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stats.csv
    touch ${prefix}_stats.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stats: \$(samtools --version |& sed '1!d ; s/samtools //')
    END_VERSIONS
    """
}

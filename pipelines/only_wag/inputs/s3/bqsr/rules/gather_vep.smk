
def get_recal_vcfs(wildcards):
    # interval dir from split intervals
    ivals_dir = checkpoints.split_intervals.get(**wildcards).output[0]
    # variable number of intervals up to scatter_size set in config (default: 50)
    INTERVALS, = glob_wildcards(os.path.join(ivals_dir,"00{interval}-scattered.interval_list"))
    # return list of split intervals recal.vcf.gz
    return sorted(expand(
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/money/var_recal/apply/money_00{interval}/recal.00{interval}.vcf.gz",
        bucket = config['bucket'],
        breed=breed,
        sample_name = sample_name,
        ref = config['ref'],
        interval = INTERVALS
    ))

rule final_gather_vcfs:
    input:
        get_recal_vcfs
    output:
        final_vcf       = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/money/final_gather/{breed}_{sample_name}.{ref}.vcf.gz"),
        final_vcf_index = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/money/final_gather/{breed}_{sample_name}.{ref}.vcf.gz.tbi")
    params:
        vcfs = lambda wildcards, input: " --input ".join(map(str,input)),
    threads: 4
    resources:
         time   = 240,
         mem_mb = 22000
    shell:
        '''
            set -e

            gatk --java-options "-Xmx18g -Xms6g" \
                GatherVcfsCloud \
                --ignore-safety-checks \
                --gather-type BLOCK \
                --input {params.vcfs} \
                --output {output.final_vcf}

            gatk --java-options "-Xmx18g -Xms6g" \
                IndexFeatureFile \
                --input {output.final_vcf}
        '''

rule vep_by_interval:
    input:
        recal_vcf = "{bucket}/wgs/{breed}/{sample_name}/{ref}/money/var_recal/apply/money_00{interval}/recal.00{interval}.vcf.gz",
    output:
        recal_vep     = "{bucket}/wgs/{breed}/{sample_name}/{ref}/money/final_gather/vep/money_00{interval}/recal.00{interval}.vep.vcf.gz", 
        recal_vep_tbi = "{bucket}/wgs/{breed}/{sample_name}/{ref}/money/final_gather/vep/money_00{interval}/recal.00{interval}.vep.vcf.gz.tbi", 
    params:
        out_name  = lambda wildcards, output: os.path.splitext(output.recal_vep)[0],
        ref_fasta = config["ref_fasta"],
        ref_gtf   = config["ref_gtf"]
    threads: 6
    resources:
         time   = 720,
         mem_mb = 60000
    shell:
        '''
            set -e

            source activate ensembl-vep

            vep \
                -i {input.recal_vcf} \
                -o {params.out_name} \
                --gtf {params.ref_gtf} \
                --fasta {params.ref_fasta} \
                --fork 4 \
                --everything \
                --force_overwrite \
                --vcf \
                --dont_skip

            bgzip --threads 6 -c {params.out_name} > {output.recal_vep}
            tabix -p vcf {output.recal_vep}
        '''

def get_vep_vcfs(wildcards):
    # interval dir from split intervals
    ivals_dir = checkpoints.split_intervals.get(**wildcards).output[0]
    # variable number of intervals up to scatter_size set in config (default: 50)
    INTERVALS, = glob_wildcards(os.path.join(ivals_dir,"00{interval}-scattered.interval_list"))
    # return list of split intervals recal.vcf.gz
    return sorted(expand(
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/money/final_gather/vep/money_00{interval}/recal.00{interval}.vep.vcf.gz",
        bucket = config['bucket'],
        breed=breed,
        sample_name = sample_name,
        ref = config['ref'],
        interval = INTERVALS
    ))

rule final_gather_veps:
    input:
        get_vep_vcfs
    output:
        vep_vcf       = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/money/final_gather/{breed}_{sample_name}.{ref}.vep.vcf.gz"),
        vep_vcf_index = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/money/final_gather/{breed}_{sample_name}.{ref}.vep.vcf.gz.tbi"),
    params:
        vcf_tmp = "{bucket}/wgs/{breed}/{sample_name}/{ref}/money/final_gather/joint_genotype.{ref}.TMP.gz",
        veps    = lambda wildcards, input: " --input ".join(map(str,input)),
    threads: 24
    resources:
         time   = 1440,
         mem_mb = 22000
    shell:
        '''
            set -e

            gatk --java-options "-Xmx18g -Xms6g" \
                GatherVcfsCloud \
                --ignore-safety-checks \
                --gather-type BLOCK \
                --input {params.veps} \
                --output {params.vcf_tmp}

            zcat {params.vcf_tmp} | bgzip --threads 24 -c > {output.vep_vcf} &&
            tabix -p vcf {output.vep_vcf}

            rm -f {params.vcf_tmp}
        '''


# Defines the AWS Athena workgroup and Glue catalog database for the project.

# This resource creates an Athena workgroup for running queries.
resource "aws_athena_workgroup" "main" {
  name = var.project_name

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"
    }
  }
}

# This resource creates a Glue catalog database for storing metadata about the raw data in the S3 bucket.
resource "aws_glue_catalog_database" "main" {
  name = replace(var.project_name, "-", "_")
}

# This resource creates a Glue catalog table for the recently played tracks data, which is stored in Parquet format in the S3 bucket.
resource "aws_glue_catalog_table" "recently_played" {
  name          = "recently_played"
  database_name = aws_glue_catalog_database.main.name

  table_type = "EXTERNAL_TABLE"

  parameters = { # Defines the table parameters, including the storage format and partitioning information.
    EXTERNAL = "TRUE"
    classification = "parquet"
    "projection.enabled" = "true"
    "projection.dt.type" = "date"
    "projection.dt.format" = "yyyy/MM/dd"
    "projection.dt.range" = "2026/09/01,NOW"
    "projection.dt.interval" = "1"
    "projection.dt.interval.unit" = "DAYS"
    "storage.location.template" = "s3://${aws_s3_bucket.raw_data.bucket}/processed/recently_played/dt=$${dt}/"
  }

  partition_keys {
    name = "dt"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.raw_data.bucket}/processed/recently_played/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info { # Defines the serialization library used for reading and writing Parquet files in the Glue catalog table.
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    # Defines the columns in the Glue catalog table, including their names and data types.
    columns {
      name = "played_at"
      type = "timestamp"
    }
    columns {
      name = "track_name"
      type = "string"
    }
    columns {
      name = "track_id"
      type = "string"
    }
    columns {
      name = "artist_names"
      type = "string"
    }
    columns {
      name = "album_name"
      type = "string"
    }
    columns {
      name = "album_release_date"
      type = "string"
    }
    columns {
      name = "duration_sec"
      type = "double"
    }

  }
}
# Configure the Confluent Provider
terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "1.23.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

resource "confluent_environment" "prod" {
  display_name = "${var.my_prefix}env"

  //lifecycle {
    //prevent_destroy = true
  //}
}

resource "confluent_kafka_cluster" "basic" {
  display_name = "${var.my_prefix}basic"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = "us-east-2"
  basic {}

  environment {
    id = confluent_environment.prod.id
  }

  //lifecycle {
    //prevent_destroy = true
  //}
}

resource "confluent_service_account" "sa-cloud" {
  display_name = "${var.my_prefix}sa-1"
  description  = "Service Account for testing"
}

resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name = "${var.my_prefix}api-key"
  description  = "Kafka API Key that is owned by created service account"
  owner {
    id          = confluent_service_account.sa-cloud.id
    api_version = confluent_service_account.sa-cloud.api_version
    kind        = confluent_service_account.sa-cloud.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = confluent_environment.prod.id
    }
  }

  //lifecycle {
    //prevent_destroy = true
  //}
}


resource "confluent_kafka_acl" "describe-basic-cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.sa-cloud.id}"
  host          = "*"
  operation     = "ALL"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }

  //lifecycle {
    //prevent_destroy = true
  //}
}

resource "confluent_role_binding" "cluster-rb" {
  principal   = "User:${confluent_service_account.sa-cloud.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = "${confluent_kafka_cluster.basic.rbac_crn}"
}

resource "confluent_kafka_topic" "orders" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name         = "transaction_data"
  partitions_count   = 3
  rest_endpoint      = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }

  //lifecycle {
    //prevent_destroy = true
  //}
}

resource "confluent_kafka_topic" "account" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name         = "payment_data"
  partitions_count   = 3
  rest_endpoint      = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }

  //lifecycle {
    //prevent_destroy = true
  //}
}

data "confluent_schema_registry_region" "example" {
  cloud   = "AWS"
  region  = "us-east-2"
  package = "ESSENTIALS"
}

resource "confluent_schema_registry_cluster" "schema_registry" {
  package = data.confluent_schema_registry_region.example.package

  environment {
    id = confluent_environment.prod.id
  }

  region {
    # See https://docs.confluent.io/cloud/current/stream-governance/packages.html#stream-governance-regions
    id = "sgreg-1"
  }

  //lifecycle {
    //prevent_destroy = true
  //}
}

//ksqldb
resource "confluent_service_account" "app-ksql" {
  display_name = "${var.my_prefix}app-ksql"
  description  = "Service account to manage 'example' ksqlDB cluster"

  //lifecycle {
    //prevent_destroy = true
  //}
}

resource "confluent_role_binding" "app-ksql-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-ksql.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn

  //lifecycle {
    //prevent_destroy = true
  //}
}

resource "confluent_role_binding" "app-ksql-schema-registry-resource-owner" {
  principal   = "User:${confluent_service_account.app-ksql.id}"
  role_name   = "ResourceOwner"
  crn_pattern = format("%s/%s", confluent_schema_registry_cluster.schema_registry.resource_name, "subject=*")

  //lifecycle {
    //prevent_destroy = true
  //}
}

resource "confluent_ksql_cluster" "example" {
  display_name = "${var.my_prefix}ksqldb"
  csu          = 1
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  credential_identity {
    id = confluent_service_account.app-ksql.id
  }
  environment {
    id = confluent_environment.prod.id
  }
  depends_on = [
    confluent_role_binding.app-ksql-kafka-cluster-admin,
    confluent_role_binding.app-ksql-schema-registry-resource-owner,
    confluent_schema_registry_cluster.schema_registry
  ]

  //lifecycle {
    //prevent_destroy = true
  //}
}

resource "confluent_connector" "postgre-sql" {
  environment {
    id = confluent_environment.prod.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-amazon-dynamo-db-sink.html#configuration-properties
  config_sensitive = {
    "aws.access.key.id"     = "***REDACTED***"
    "aws.secret.access.key" = "***REDACTED***"
  }

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-amazon-dynamo-db-sink.html#configuration-properties
  config_nonsensitive = {
    "topics" = confluent_kafka_topic.orders.topic_name
    "connector.class" = "PostgresCdcSource",
    "name" = "PostgresCdcSourceConnector_0",
    "kafka.auth.mode" = "KAFKA_API_KEY",
    "kafka.api.key" = "****************",
    "kafka.api.secret" = "****************************************************************",
    "database.hostname" = "debezium-1.<host-id>.us-east-2.rds.amazonaws.com",
    "database.port" = "5432",
    "database.user" = "postgres",
    "database.password" = "**************",
    "database.dbname" = "postgres",
    "database.server.name" = "cdc",
    "table.include.list" = "public.passengers",
    "plugin.name" =  "pgoutput",
    "output.data.format" = "JSON",
    "tasks.max" = "1"
  }
}

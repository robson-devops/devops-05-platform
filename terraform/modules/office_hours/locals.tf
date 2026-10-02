locals {
  # Ordem: banco liga antes da aplicação e desliga depois dela.
  schedule = {
    banco-liga = {
      cron   = "cron(0 ${var.start_hour} ? * ${var.weekdays} *)"
      target = "arn:aws:scheduler:::aws-sdk:rds:startDBInstance"
      input  = jsonencode({ DbInstanceIdentifier = var.database.identifier })
    }
    app-liga = {
      cron   = "cron(20 ${var.start_hour} ? * ${var.weekdays} *)"
      target = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
      input  = jsonencode({ Cluster = var.service.cluster_name, Service = var.service.name, DesiredCount = var.desired_count })
    }
    app-desliga = {
      cron   = "cron(0 ${var.stop_hour} ? * ${var.weekdays} *)"
      target = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
      input  = jsonencode({ Cluster = var.service.cluster_name, Service = var.service.name, DesiredCount = 0 })
    }
    banco-desliga = {
      cron   = "cron(10 ${var.stop_hour} ? * ${var.weekdays} *)"
      target = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance"
      input  = jsonencode({ DbInstanceIdentifier = var.database.identifier })
    }
  }
}

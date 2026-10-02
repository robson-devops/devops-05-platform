locals {
  identifier = "${var.name_prefix}-db"
  log_export = ["postgresql", "upgrade"]
}

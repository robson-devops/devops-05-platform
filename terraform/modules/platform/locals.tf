locals {
  name_prefix = "${var.project_name}-${var.environment}"

  origin_verify_header = {
    name  = "X-Origin-Verify"
    value = random_password.origin_verify.result
  }
}

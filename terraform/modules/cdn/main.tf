# Políticas gerenciadas: API sem cache, todos os cabeçalhos menos o Host, cabeçalhos de segurança.
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "main" {
  # checkov:skip=CKV_AWS_68: WAF documentado em docs/producao.md.
  # checkov:skip=CKV2_AWS_47: WAF documentado em docs/producao.md.
  # checkov:skip=CKV_AWS_86: log de acesso fica no ALB.
  # checkov:skip=CKV_AWS_174: o certificado padrão *.cloudfront.net não permite fixar a versão mínima do TLS.
  # checkov:skip=CKV2_AWS_42: certificado próprio exige domínio; ver docs/producao.md.
  # checkov:skip=CKV_AWS_310: uma origem só; failover de origem não se aplica.
  # checkov:skip=CKV_AWS_374: sem restrição geográfica.
  # checkov:skip=CKV_AWS_305: API sem página raiz.
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = var.price_class
  comment         = "${var.name_prefix}: HTTPS na borda para o ALB"

  origin {
    origin_id   = "alb"
    domain_name = var.origin_domain_name

    # Sem domínio próprio o ALB não tem certificado; o trecho até ele é HTTP.
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = var.origin_verify_header.name
      value = var.origin_verify_header.value
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = var.name_prefix
  }
}

resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.27.0"
  namespace        = "vault"
  create_namespace = true

  values = [
    yamlencode({
      global = {
        enabled = true
      }
      injector = {
        enabled = true
        authPath = "auth/jwt"
      }
      server = {
        serviceAccount = {
          create = true
          name   = "vault"
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.vault_server_irsa.arn
          }
        }
        # Dev mode enabled for turnkey reference demonstration; switch to ha/raft with seal "awskms" in prod
        dev = {
          enabled      = true
          devRootToken = "root"
        }
      }
      ui = {
        enabled     = true
        serviceType = "ClusterIP"
      }
    })
  ]

  depends_on = [module.eks]
}

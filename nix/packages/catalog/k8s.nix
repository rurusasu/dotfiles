# Package identities and provider declarations for k8s.
{ pkgs, ... }:
{
  kind = {
    pkg = pkgs.kind;
    winget = null;
    category = "k8s";
  };

  kubectl = {
    pkg = pkgs.kubectl;
    winget = null;
    category = "k8s";
  };

  kubernetes-helm = {
    pkg = pkgs.kubernetes-helm;
    winget = null;
    category = "k8s";
  };

  k9s = {
    pkg = pkgs.k9s;
    winget = null;
    category = "k8s";
  };

  kubectx = {
    pkg = pkgs.kubectx;
    winget = null;
    category = "k8s";
  };

  kustomize = {
    pkg = pkgs.kustomize;
    winget = null;
    category = "k8s";
  };

  stern = {
    pkg = pkgs.stern;
    winget = null;
    category = "k8s";
  };

  argocd = {
    pkg = pkgs.argocd;
    winget = null;
    category = "k8s";
  };

  cilium-cli = {
    pkg = pkgs.cilium-cli;
    winget = null;
    category = "k8s";
  };

  kubeseal = {
    pkg = pkgs.kubeseal;
    winget = null;
    category = "k8s";
  };

  sops = {
    pkg = pkgs.sops;
    winget = null;
    category = "k8s";
  };

  trivy = {
    pkg = pkgs.trivy;
    winget = null;
    category = "k8s";
  };

  dive = {
    pkg = pkgs.dive;
    winget = null;
    category = "k8s";
  };
}

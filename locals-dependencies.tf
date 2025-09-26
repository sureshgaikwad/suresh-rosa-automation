##############################################################
# OpenShift Features and Dependencies Logic
##############################################################

locals {
  # Dependency logic: When OpenShift AI is enabled, automatically enable prerequisite operators
  # This ensures that all required dependencies are deployed when OpenShift AI is requested
  deploy_nfd                             = var.deploy_openshift_ai ? true : var.deploy_nfd
  deploy_nvidia_gpu_operator             = var.deploy_openshift_ai ? true : var.deploy_nvidia_gpu_operator
  deploy_nfd_application                 = var.deploy_openshift_ai ? true : var.deploy_nfd_application
  deploy_nvidia_gpu_operator_application = var.deploy_openshift_ai ? true : var.deploy_nvidia_gpu_operator_application
  deploy_openshift_servicemesh           = var.deploy_openshift_ai ? true : var.deploy_openshift_servicemesh
  deploy_openshift_serverless            = var.deploy_openshift_ai ? true : var.deploy_openshift_serverless
  deploy_openshift_lightspeed            = var.deploy_openshift_ai ? true : var.deploy_openshift_lightspeed
}
An Example Grafana Deployment
=============================

Someone has asked to see a demo of Grafana with your corporate
data. You don't need a full production instance of Grafana, just a
sample server. Since it's corporate data though, it does need to be
protected.

This code deploys a quick and dirty Grafana into Amazon Fargate with
integration into AWS Cognito.

The dashboards will be created by Terraform so that we don't need
persistent storage.

Running the Demo
----------------

You will need a VPC with at least two subnets as well as at least one
domain hosted in Route 53.

Create terraform.tfvars with definitions for the following variables
* vpc_id
* private_subnets
* public_subnets
* dns_domain
* dns_zone_id

Run ``terraform apply`` to deploy Grafana. This will output the URL
for the Grafana application.

Login into Grafana with the default username and password of
admin/admin. Change the admin password.

Now change directory into ``samples`` and set the variables
grafana_url and grafana_auth in a new terraform.tfvars file. Run
``terraform apply`` to deploy a trivial dashboard for CloudWatch EBS
metrics.



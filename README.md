# Pipeline Demo

* Based on instructions at <https://mojo.redhat.com/docs/DOC-1175874>.
* To deploy everything, just execute `make`. This will do the following:
	1. Install the default templates and quickstarts (if necessary).
	2. Install gogs.
	3. Create a user in gogs (username `gogs`, password `gogs`).
	4. Install the `cart` source into gogs.
	5. Install nexus (username `admin`, password `admin123`).
	6. Configure nexus as a proxy repository to Red Hat GA.
	7. Setup a build pipeline based on the `cart` git repo.
	8. Setup the production environment.
* Note: Do not be alarmed if you get the following error while running `make` - it is normal and expected:

````
The ImageStream "cart" is invalid: []: Internal error: imagestreams "cart" is invalid: spec.tags[prod].from.name: Not found: "cart:prod"
make: [setupprod] Error 1 (ignored)
````

## Gogs to OpenShift Integration

* The installation is automated for the most part except for the Gogs to OpenShift integration. This is to kick off a build whenever new code in pushed to Gogs.
* Follow these steps to perform the integration:
	* Get the webhook for the pipeline.
		* Login to the OpenShift web console, select the `development` project.
		* Select `Builds` / `Pipelines`.
		* Click on the link for the newly-created pipeline.
		* Click on `Configuration`, then copy the `Generic Webhook URL` under `Triggers`.
	* Add a new Gogs Webhook.
		* Go to the `cart` repo - http://GOGS_HOST/gogs/cart
		* Click on `Settings`.
		* Click on Webhooks in the left pane, click Add Webhook, and select Gogs.
		* Enter the generic webhook URL that you copied earlier into the Payload URL field.
		* Set `When should this webhook be triggered?` to `Just the push event`.
		* Click `Add Webhook`.


## Development Environment

* The Jenkins pipeline is located at `cart-spring-boot/Jenskinsfile`. If you need to modify the pipeline and you need help with the Jenkins OpenShift Client Plugin, you can refer [here](https://github.com/openshift/jenkins-client-plugin).
* `cart-spring-boot` was cloned from <https://github.com/openshift-labs/devops-labs.git>.


## Deploying the app without the pipeline

If you just want to deploy the cart without setting up the pipeline,

````
oc new-app \
  java:8~http://gogs-lab-infra.192.168.64.6.nip.io/gogs/cart.git \
  --name=cart \
  --build-env=MAVEN_MIRROR_URL=http://nexus.lab-infra.svc:8081/repository/content/groups/public/
````

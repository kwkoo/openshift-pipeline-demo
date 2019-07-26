BASE=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

INFRA_PROJECT=lab-infra
GOGS_APP_NAME=gogs
NEXUS_ADMIN_USER=admin
NEXUS_ADMIN_PASSWORD=admin123
NEXUS_APP_NAME=nexus
DEV_PROJECT=development
PROD_PROJECT=production
PIPELINE_APP_NAME=pipeline
CART_APP_NAME=cart
CART_REPO_URI=gogs/$(CART_APP_NAME).git
ROUTING_SUFFIX=$(shell $(BASE)/scripts/getroutingsuffix)
MASTER_URL=$(shell $(BASE)/scripts/masterurl)
ON_RHPDS=$(shell $(BASE)/scripts/onrhpds)


# Uncomment this block if you are installing it on RHPDS but are not running
# this on the bastion. Be sure to set GUID to a value which is appropriate for
# your environment.
#
#GUID=XXX-XXXX
#ON_RHPDS=1
#MASTER_URL=https://master.$(GUID).openshiftworkshop.com
#ROUTING_SUFFIX=apps.$(GUID).openshiftworkshop.com



# Set this if you need to install templates and quickstarts.
REGISTRY_USERNAME=
REGISTRY_PASSWORD=


################################################################################
#                                                                              #
# You should not need to change anything below this block.                     #
#                                                                              #
################################################################################

NEXUS_URL=http://$(NEXUS_APP_NAME)-$(INFRA_PROJECT).$(ROUTING_SUFFIX)


ifeq ($(ON_RHPDS), 1)
	INFRA_OC_USER=user1
else
	INFRA_OC_USER=developer
endif

DEV_OC_USER=$(INFRA_OC_USER)
PROD_OC_USER=$(INFRA_OC_USER)


.PHONY: printvar deployall depoytemplates deploygogs waitforgogs setupgogs deploynexus \
waitfornexus configrepos deploypipeline setupprod clean console gogs jenkins \
info loopinfo endpoint

deployall: printvar deploytemplates setupgogs configrepos deploypipeline setupprod
	@echo "Done"

help:
	@echo "Make targets:"
	@echo "deployall - Deploy the demo."
	@echo "clean - Delete all projects created by deployall."
	@echo "console - OpenShift console."
	@echo "gogs - cart repo in Gogs."
	@echo "jenkins - Jenkins web UI."
	@echo "info - Send a curl request to the cart /api/cart/info endpoint."
	@echo "loopinfo - Continually perform a curl request to cart."
	@echo "endpoint - CartEndpoint.java in Gogs."

printvar:
	@echo "MASTER_URL = $(MASTER_URL)"
	@echo "ROUTING_SUFFIX = $(ROUTING_SUFFIX)"
	@echo "ON_RHPDS = $(ON_RHPDS)"
	@echo "NEXUS_URL = $(NEXUS_URL)"
	@echo "INFRA_PROJECT = $(INFRA_PROJECT)"
	@echo "GOGS_APP_NAME = $(GOGS_APP_NAME)"
	@echo "NEXUS_ADMIN_USER = $(NEXUS_ADMIN_USER)"
	@echo "NEXUS_ADMIN_PASSWORD = $(NEXUS_ADMIN_PASSWORD)"
	@echo "NEXUS_APP_NAME = $(NEXUS_APP_NAME)"
	@echo "DEV_PROJECT = $(DEV_PROJECT)"
	@echo "PROD_PROJECT = $(PROD_PROJECT)"
	@echo "PIPELINE_APP_NAME = $(PIPELINE_APP_NAME)"
	@echo "CART_APP_NAME = $(CART_APP_NAME)"
	@echo "CART_REPO_URI = $(CART_REPO_URI)"
	@echo "REGISTRY_USERNAME = $(REGISTRY_USERNAME)"
	@echo "REGISTRY_PASSWORD = $(REGISTRY_PASSWORD)"
	@echo
	@echo "Press enter to proceed"
	@read

deploytemplates:
	@if [ $(ON_RHPDS) -ne 1 ]; then \
	  if [ -z "$(REGISTRY_USERNAME)" -o -z "$(REGISTRY_PASSWORD)" ]; then \
	    echo "Error: You need to set the REGISTRY_USERNAME and REGISTRY_PASSWORD variables"; \
		exit 1; \
	  fi; \
	fi
	-@if [ $(ON_RHPDS) -eq 1 ]; then \
		echo "Running on RHPDS - do not need to install default templates"; \
	else \
		echo "Not running on RHPDS - we need to install default templates"; \
		oc login -u system:admin; \
		oc create secret docker-registry imagestreamsecret \
		  --docker-username="$(REGISTRY_USERNAME)" \
		  --docker-password="$(REGISTRY_PASSWORD)" \
		  --docker-server=registry.redhat.io \
		  -n openshift \
		  --as system:admin; \
		oc create \
		  -f https://raw.githubusercontent.com/openshift/library/master/official/java/templates/openjdk-web-basic-s2i.json \
		  -n openshift; \
		oc create \
		  -f https://raw.githubusercontent.com/jboss-openshift/application-templates/ose-v1.4.16/openjdk/openjdk18-image-stream.json \
		  -n openshift; \
	fi

deploygogs:
	@echo "Deploying gogs..."
	@oc login -u $(INFRA_OC_USER) -p openshift
	@$(BASE)/scripts/switchtoproject $(INFRA_PROJECT)
	@oc process \
	  -f $(BASE)/yaml/gogs-template.yaml \
	  -p PROJECT=$(INFRA_PROJECT) \
	  -p ROUTING_SUFFIX=$(ROUTING_SUFFIX) \
	| \
	oc create -f -
	@oc rollout latest dc/postgresql-gogs

waitforgogs: deploygogs
	@$(BASE)/scripts/waitforgogs $(INFRA_PROJECT)

setupgogs: waitforgogs
	@echo "Creating gogs user..."
	@oc rsh dc/postgresql-gogs /bin/sh -c 'LD_LIBRARY_PATH=/opt/rh/rh-postgresql10/root/usr/lib64 /opt/rh/rh-postgresql10/root/usr/bin/psql -U gogs -d gogs -c "INSERT INTO public.user (lower_name,name,email,passwd,rands,salt,max_repo_creation,avatar,avatar_email,num_repos) VALUES ('"'gogs','gogs','gogs@gogs,com','40d76f42148716323d6b398f835438c7aec43f41f3ca1ea6e021192f993e1dc4acd95f36264ffe16812a954ba57492f4c107','konHCHTY7M','9XecGGR6cW',-1,'e4eba08430c43ef06e425e2e9b7a740f','gogs@gogs.com',1"')"'
	@$(BASE)/scripts/pushtogogs $(INFRA_PROJECT) gogs gogs $(CART_REPO_URI)

deploynexus:
	@echo "Deploying nexus..."
	@oc login -u $(INFRA_OC_USER) -p openshift
	@$(BASE)/scripts/switchtoproject $(INFRA_PROJECT)
	@oc process \
	  -f $(BASE)/yaml/xpaas-nexus-persistent.yaml \
	  -p APPLICATION_NAME=nexus \
	  -p VOLUME_CAPACITY=512Mi \
	| \
	oc create -f -

waitfornexus: deploynexus
	@$(BASE)/scripts/waitfornexus $(INFRA_PROJECT)

configrepos: waitfornexus
	@echo "Configuring nexus proxy registry..."
	@curl \
	  -u $(NEXUS_ADMIN_USER):$(NEXUS_ADMIN_PASSWORD) \
	  -X POST \
	  -H "Content-Type: application/json" \
	  -d "{\"data\":{\"repoType\":\"proxy\",\"id\":\"redhat-ga\",\"name\":\"Red Hat GA\",\"browseable\":true,\"indexable\":true,\"notFoundCacheTTL\":1440,\"artifactMaxAge\":-1,\"metadataMaxAge\":1440,\"itemMaxAge\":1440,\"repoPolicy\":\"RELEASE\",\"provider\":\"maven2\",\"providerRole\":\"org.sonatype.nexus.proxy.repository.Repository\",\"downloadRemoteIndexes\":true,\"autoBlockActive\":true,\"fileTypeValidation\":true,\"exposed\":true,\"checksumPolicy\":\"WARN\",\"remoteStorage\":{\"remoteStorageUrl\":\"https://maven.repository.redhat.com/ga/\",\"authentication\":null,\"connectionSettings\":null}}}" \
	  -S \
	  $(NEXUS_URL)/service/local/repositories \
	>> /dev/null
	@echo "Configuring public repositories..."
	@curl \
	  -u $(NEXUS_ADMIN_USER):$(NEXUS_ADMIN_PASSWORD) \
	  -X PUT \
	  -H "Content-Type: application/json" \
	  -d '{"data":{"id":"public","name":"Public Repositories","format":"maven2","exposed":true,"provider":"maven2","repositories":[{"id":"releases"},{"id":"snapshots"},{"id":"thirdparty"},{"id":"central"},{"id":"redhat-ga"},{"id":"apache-snapshots"}]}}' \
	  -S \
	  $(NEXUS_URL)/service/local/repo_groups/public \
	>> /dev/null

deploypipeline:
	@oc login -u $(DEV_OC_USER) -p openshift
	@$(BASE)/scripts/switchtoproject $(DEV_PROJECT)
	@echo "Deploying dev artifacts..."
	@oc process \
	  -f $(BASE)/yaml/dev-template.yaml \
	  --local \
	  -p APP_NAME=$(CART_APP_NAME) \
	| \
	oc create -f -
	@echo "Deploying pipeline..."
	# Note: If you intend to use this against a Nexus 3 server, NEXUS_URL
	# should be changed to
	# http://$(NEXUS_APP_NAME).$(INFRA_PROJECT).svc:8081/repository/maven-all-public
	@oc new-app \
	  http://$(GOGS_APP_NAME)-$(INFRA_PROJECT).$(ROUTING_SUFFIX)/$(CART_REPO_URI) \
	  --name=$(PIPELINE_APP_NAME) \
	  --build-env NEXUS_URL=http://$(NEXUS_APP_NAME).$(INFRA_PROJECT).svc:8081/content/groups/public \
	  --build-env DEV_PROJ=$(DEV_PROJECT) \
	  --build-env PROD_PROJ=$(PROD_PROJECT)
	@$(BASE)/scripts/patchjenkins $(DEV_PROJECT)

setupprod:
	@echo "Setting up production project..."
	@oc login -u $(PROD_OC_USER) -p openshift
	@$(BASE)/scripts/switchtoproject $(PROD_PROJECT)
	@oc create \
	  -f https://raw.githubusercontent.com/openshift-labs/devops-labs/ocp-3.11/openshift/coolstore-deployment-template.yaml
	-@oc process coolstore-deployments \
	  -p HOSTNAME_SUFFIX=$(shell oc project -q).$(ROUTING_SUFFIX) \
	| \
	oc create -f - 2>/dev/null
	# Let the jenkins user promote images to the production project.
	@oc policy add-role-to-user \
	  edit \
	  system:serviceaccount:$(DEV_PROJECT):jenkins \
	  -n $(PROD_PROJECT)
	# Setup readiness and liveness checks.
	@oc set probe -n $(PROD_PROJECT) dc/cart \
	  --liveness \
	  --readiness \
	  --initial-delay-seconds=15 \
	  --get-url=http://:8080/api/cart/info
	# Setup rolling deployment.
	oc patch -n $(PROD_PROJECT) dc/cart \
	  --patch '{"spec": {"strategy": {"type": "Rolling", "rollingParams": {"maxSurge": 1, "maxUnavailable": 0, "timeoutSeconds": 600}}}}'

clean:
	@echo "Removing projects..."
	-@oc delete project $(INFRA_PROJECT)
	-@oc delete project $(DEV_PROJECT)
	-@oc delete project $(PROD_PROJECT)

console:
	$(eval URL="`$(BASE)/scripts/masterurl`/console")
	@if [ "$(shell uname)" = "Darwin" ]; then \
	  open ${URL}; \
	else \
	  echo "${URL}"; \
	fi

gogs:
	$(eval URL="http://$(GOGS_APP_NAME)-$(INFRA_PROJECT).$(ROUTING_SUFFIX)/gogs/cart")
	@if [ "$(shell uname)" = "Darwin" ]; then \
	  open ${URL}; \
	else \
	  echo "${URL}"; \
	fi

jenkins:
	$(eval URL="https://jenkins-$(DEV_PROJECT).$(ROUTING_SUFFIX)")
	@if [ "$(shell uname)" = "Darwin" ]; then \
	  open ${URL}; \
	else \
	  echo "${URL}"; \
	fi

info:
	@curl http://cart-$(PROD_PROJECT).$(ROUTING_SUFFIX)/api/cart/info
	@echo

loopinfo:
	@while true; do \
	  curl http://cart-$(PROD_PROJECT).$(ROUTING_SUFFIX)/api/cart/info; \
	  echo; \
	  sleep 1; \
	done

endpoint:
	$(eval URL="http://$(GOGS_APP_NAME)-$(INFRA_PROJECT).$(ROUTING_SUFFIX)/gogs/cart/src/master/src/main/java/com/redhat/coolstore/rest/CartEndpoint.java")
	@if [ "$(shell uname)" = "Darwin" ]; then \
	  open ${URL}; \
	else \
	  echo "${URL}"; \
	fi

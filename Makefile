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
SKIP_TEMPLATES_PROVISION=$(shell $(BASE)/scripts/onrhpds)


# Uncomment this block if you are installing it on RHPDS but are not running
# this on the bastion. Be sure to set GUID to a value which is appropriate for
# your environment.
#
#GUID=XXX-XXXX
#SKIP_TEMPLATES_PROVISION=1
#ROUTING_SUFFIX=apps.$(GUID).open.redhat.com


# Uncomment this block if you are installing it on opentlc.
#
#GUID=na311
#PROJ_PREFIX=XXX-
#INFRA_PROJECT=$(PROJ_PREFIX)lab-infra
#DEV_PROJECT=$(PROJ_PREFIX)dev
#PROD_PROJECT=$(PROJ_PREFIX)prod
#SKIP_TEMPLATES_PROVISION=1
#ROUTING_SUFFIX=apps.$(GUID).openshift.opentlc.com


# Set this if you need to install templates and quickstarts.
REGISTRY_USERNAME=
REGISTRY_PASSWORD=


################################################################################
#                                                                              #
# You should not need to change anything below this block.                     #
#                                                                              #
################################################################################

NEXUS_URL=http://$(NEXUS_APP_NAME)-$(INFRA_PROJECT).$(ROUTING_SUFFIX)


ifeq ($(SKIP_TEMPLATES_PROVISION), 1)
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
	@echo "ROUTING_SUFFIX = $(ROUTING_SUFFIX)"
	@echo "SKIP_TEMPLATES_PROVISION = $(SKIP_TEMPLATES_PROVISION)"
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
	@echo "Ensure that you have logged in using the oc tool before you proceed"
	@echo "Press enter to proceed"
	@read

deploytemplates:
	@if [ $(SKIP_TEMPLATES_PROVISION) -ne 1 ]; then \
	  if [ -z "$(REGISTRY_USERNAME)" -o -z "$(REGISTRY_PASSWORD)" ]; then \
	    echo "Error: You need to set the REGISTRY_USERNAME and REGISTRY_PASSWORD variables"; \
		exit 1; \
	  fi; \
	fi
	-@if [ $(SKIP_TEMPLATES_PROVISION) -eq 1 ]; then \
		echo "Skipping install of default templates"; \
	else \
		echo "We need to install default templates"; \
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
	@if [ $(SKIP_TEMPLATES_PROVISION) -ne 1 ]; then \
	  @oc login -u $(INFRA_OC_USER) -p openshift; \
	fi
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
	@if [ $(SKIP_TEMPLATES_PROVISION) -ne 1 ]; then \
	  @oc login -u $(INFRA_OC_USER) -p openshift; \
	fi
	@$(BASE)/scripts/switchtoproject $(INFRA_PROJECT)
	@oc new-app \
	  -f https://raw.githubusercontent.com/OpenShiftDemos/nexus/master/nexus3-template.yaml \
	  --param=NEXUS_VERSION=3.13.0 \
	  --param=MAX_MEMORY=2Gi

waitfornexus: deploynexus
	@$(BASE)/scripts/waitfornexus $(INFRA_PROJECT)

configrepos: waitfornexus
	@echo "Configuring nexus proxy registry..."
	@$(BASE)/scripts/addnexusrepos $(INFRA_PROJECT)

deploypipeline:
	@if [ $(SKIP_TEMPLATES_PROVISION) -ne 1 ]; then \
	  @oc login -u $(DEV_OC_USER) -p openshift; \
	fi
	@$(BASE)/scripts/switchtoproject $(DEV_PROJECT)
	@echo "Deploying dev artifacts..."
	@oc process \
	  -f $(BASE)/yaml/dev-template.yaml \
	  --local \
	  -p APP_NAME=$(CART_APP_NAME) \
	| \
	oc create -f -
	@echo "Deploying jenkins..."
	@oc new-app \
	  jenkins-ephemeral \
	  --param=MEMORY_LIMIT=4Gi
	@echo "Deploying pipeline..."
	@oc new-app \
	  http://$(GOGS_APP_NAME)-$(INFRA_PROJECT).$(ROUTING_SUFFIX)/$(CART_REPO_URI) \
	  --name=$(PIPELINE_APP_NAME) \
	  --build-env NEXUS_URL=http://$(NEXUS_APP_NAME).$(INFRA_PROJECT).svc:8081/repository/maven-all-public \
	  --build-env DEV_PROJ=$(DEV_PROJECT) \
	  --build-env PROD_PROJ=$(PROD_PROJECT)
	@if [ "$(shell oc get limits/$(DEV_PROJECT)-core-resource-limits -n $(DEV_PROJECT) -o=jsonpath='{.spec.limits[0].max.memory}')" != "6Gi" ]; then \
	  $(BASE)/scripts/patchjenkins $(DEV_PROJECT); \
	fi

setupprod:
	@echo "Setting up production project..."
	@if [ $(SKIP_TEMPLATES_PROVISION) -ne 1 ]; then \
	  @oc login -u $(PROD_OC_USER) -p openshift; \
	fi
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
	$(eval URL="http://console-openshift-console.$(ROUTING_SUFFIX)")
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



targets := os tempo victorialogs clkh

.PHONY: $(targets)

$(targets):
	echo "TARGET"="$@" > .env-target
	docker compose \
	-f docker-compose-monitoring.yaml \
	-f docker-compose-$@.yaml \
	--env-file .env-target --env-file .env \
	up --force-recreate --remove-orphans -d



# -f dokcer-compose-tracegen.yaml \


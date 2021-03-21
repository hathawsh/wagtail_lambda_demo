default: out/lambda.zip

out/lambda.zip: lambda.dockerfile lambda_function.py requirements.txt
	mkdir -p out && \
	DOCKER_BUILDKIT=1 docker build -o out -f lambda.dockerfile .

.PHONY: default

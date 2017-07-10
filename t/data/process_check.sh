#!/bin/bash

(>&2 echo "TEST error print")
echo "TEST normal print"

while [[ -z "$TESTVAR" ]]
do
	read -p "Enter something: " TESTVAR
done

echo "you entered $TESTVAR"

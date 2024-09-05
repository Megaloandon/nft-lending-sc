PUBLISHER_PROFILE=lending
PUBLISHER_ADDR=0x$(aptos config show-profiles --profile=$PUBLISHER_PROFILE | grep 'account' | sed -n 's/.*"account": \"\(.*\)\".*/\1/p')
export PUBLISHER_ADDR
echo $PUBLISHER_ADDR
OUTPUT=$(aptos move create-object-and-publish-package \
  --address-name lending_addr \
  --named-addresses lending_addr=$PUBLISHER_ADDR \
  --profile $PUBLISHER_PROFILE \
	--assume-yes)
echo "$OUTPUT" | grep "Code was successfully deployed to object address" | awk '{print $NF}' | sed 's/\.$//' > contract_address.txt
echo "Contract deployed to address: $(cat contract_address.txt)"
echo "Contract address saved to contract_address.txt"
PUBLISHER_PROFILE=lending
PUBLISHER_ADDR=0x$(aptos config show-profiles --profile=$PUBLISHER_PROFILE | grep 'account' | sed -n 's/.*"account": \"\(.*\)\".*/\1/p')
export PUBLISHER_ADDR
echo $PUBLISHER_ADDR
aptos move run-script --profile $PUBLISHER_PROFILE --assume-yes --script-path sources/scripts/RegisterCoin.move --type-args 0x8367f0e83699814840a5147b6c5216cbd2ae6687f3eb0e7242a717b506cf91d7::mega_coin::MockAPT
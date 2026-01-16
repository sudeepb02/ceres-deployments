# Retrieve a price: /prices

## Get Price Route

<mark style="color:blue;">`GET`</mark> `https://api.paraswap.io/prices`

This endpoint gets the optimal price and price route required to swap from one token to another.

You’ll find the parameters to build a successful query below:

#### Query Parameters

| Name                                           | Type    | Description                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ---------------------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| srcToken<mark style="color:red;">\*</mark>     | string  | Source Token Address. Instead **Token Symbol** could be used for tokens listed in the `/tokens` endpoint.                                                                                                                                                                                                                                                                                                                                       |
| srcDecimals<mark style="color:red;">\*</mark>  | integer | Source Token Decimals. (Can be omitted if Token Symbol is used in `srcToken`).                                                                                                                                                                                                                                                                                                                                                                  |
| destToken<mark style="color:red;">\*</mark>    | string  | Destination Token Address. Instead **Token Symbol** could be used for tokens listed in the  `/tokens` endpoint.                                                                                                                                                                                                                                                                                                                                 |
| amount<mark style="color:red;">\*</mark>       | string  | <p>srcToken amount (in case of SELL) or destToken amount (in case of BUY). <br>The amount should be in <strong>WEI/Raw units</strong> (eg. 1WBTC -> 100000000) </p>                                                                                                                                                                                                                                                                             |
| side                                           | string  | <p><strong>SELL</strong> or <strong>BUY</strong>. <br>Default: <code>SELL</code>.</p>                                                                                                                                                                                                                                                                                                                                                           |
| network                                        | string  | <p>Network ID. (Mainnet - 1, Optimism - 10, BSC - 56, Polygon - 137, Base - 8453, Arbitrum - 42161, Avalanche - 43114, Gnosis - 100, Sonic - 146, Unichain - 130, Plasma - 9745).<br>Default: <code>1</code>.</p>                                                                                                                                                                                                                               |
| otherExchangePrices                            | boolean | <p>If provided, <strong>others</strong> object is filled in the response with price quotes from other exchanges <em>(if available for comparison)</em>.<br>Default: <code>false</code></p>                                                                                                                                                                                                                                                      |
| includeDEXS                                    | string  | <p>Comma Separated List of DEXs to include. <br>All supported DEXs by chain can be found <a href="https://api.paraswap.io/adapters/list/1">here </a><br>eg: <code>UniswapV3, CurveV1</code></p>                                                                                                                                                                                                                                                 |
| excludeDEXS                                    | string  | <p>Comma Separated List of DEXs to exclude.<br>All supported DEXs by chain can be found <a href="https://api.paraswap.io/adapters/list/1">here </a><br>eg: <code>UniswapV3, CurveV1</code></p>                                                                                                                                                                                                                                                  |
| excludeRFQ                                     | boolean | <p>Exclude all RFQs from pricing <br>eg: <code>AugustusRFQ, Hashflow</code><br>Default: <code>false</code></p>                                                                                                                                                                                                                                                                                                                                  |
| includeContractMethods                         | string  | Comma Separated List of Comma Separated List of Contract Methods to include in pricing (without spaces). View the list of the supported methods for [V5 ](https://developers.paraswap.network/api/master/api-v5#supported-methods)and [V6](https://developers.paraswap.network/api/master/api-v6.2#supported-methods) eg: `swapExactAmountIn,swapExactAmountInOnUniswapV2`                                                                      |
| excludeContractMethods                         | string  | Comma Separated List of Contract Methods to exclude from pricing (without spaces). View the list of the supported methods for [V5 ](https://developers.paraswap.network/api/master/api-v5#supported-methods)and [V6](https://developers.paraswap.network/api/master/api-v6.2#supported-methods)                                                                                                                                                 |
| userAddress                                    | string  | User's Wallet Address.                                                                                                                                                                                                                                                                                                                                                                                                                          |
| route                                          | string  | <p>Dash (-) separated list of tokens (addresses or symbols from <code>/tokens</code>) to comprise the price route. <em>Max 4 tokens.</em> <br><em><strong>\*Note:</strong> If <code>route</code> is specified, the response will only comprise of the route specified which might not be the optimal route.</em> </p>                                                                                                                           |
| partner                                        | string  | Partner string.                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| destDecimals<mark style="color:red;">\*</mark> | integer | Destination Token Decimals. (Can be omitted if Token Symbol is used in `destToken`).                                                                                                                                                                                                                                                                                                                                                            |
| maxImpact                                      | number  | In %. It's a way to bypass the API price impact check (default = 15%).                                                                                                                                                                                                                                                                                                                                                                          |
| receiver                                       | String  | Receiver's Wallet address. (Can be omitted if swapping tokens from and to same account)                                                                                                                                                                                                                                                                                                                                                         |
| srcTokenTransferFee                            | string  | <p>If the source token is a tax token, you should specify the tax amount in BPS.</p><p><em>\*For example: for a token with a 5% tax, you should set it to 500 as</em><br><em><code>\[(500/10000)\*100=5%]</code></em></p><p><em>\*\*Note: not all DEXs and contract methods support trading tax tokens, so we will filter those that don't.</em> </p>                                                                                           |
| destTokenTransferFee                           | string  | <p>If the destination token is a tax token, you should specify the tax amount in BPS.</p><p><em>\*For example: for a token with a 5% tax, you should set it to 500 as</em><br><em><code>\[(500/10000)\*100=5%]</code></em></p><p><em>\*\*Note: not all DEXs and contract methods support trading tax tokens, so we will filter those that don't.</em> </p>                                                                                      |
| srcTokenDexTransferFee                         | string  | <p>If the source token is a tax token, you should specify the tax amount in BPS.<br>Some tokens only charge tax when swapped in/out DEXs and not on ordinary transfers.</p><p><em>\*For example: for a token with a 5% tax, you should set it to 500 as</em><br><em><code>\[(500/10000)\*100=5%]</code></em></p><p><em>\*\*Note: not all DEXs and contract methods support trading tax tokens, so we will filter those that don't.</em> </p>    |
| destTokenDexTransferFee                        | string  | <p>If the destination token is a tax token, you should specify the tax amount in BPS. <br>Some tokens only charge tax when swapped in/out DEXs, not on ordinary transfers.</p><p><em>\*For example: for a token with a 5% tax, you should set it to 500 as</em><br><em><code>\[(500/10000)\*100=5%]</code></em></p><p><em>\*\*Note: not all DEXs and contract methods support trading tax tokens, so we will filter those that don't.</em> </p> |
| version                                        | number  | <p>To specify the protocol version. <strong>Values:</strong> 5 or 6.2<br><strong>Default</strong>: 5</p>                                                                                                                                                                                                                                                                                                                                        |
| excludeContractMethodsWithoutFeeModel          | boolean | Specify that methods without fee support should be excluded from the price route. Default: `false`                                                                                                                                                                                                                                                                                                                                              |
| ignoreBadUsdPrice                              | boolean | If tokens USD prices are not available, `Bad USD Price` error will be thrown. Use this param to skip this check. Default: `false`                                                                                                                                                                                                                                                                                                               |

Here are two examples of a successful price response and a failed query.

The first query was a sell price request on Ethereum Mainnet (chainId: 1) using Velora's Market API. The request aimed to swap 1,000 USDC for ETH (destToken: 0xeeee...eeee) while retrieving the best possible route for the trade.

As a result, it successfully retrieved an optimized route for swapping 1,000 USDC to ETH via Uniswap V3, with minimal slippage and efficient execution while estimating gas costs.

{% tabs %}
{% tab title="200 Successful Price Response." %}

```
{
    "priceRoute": {
        "blockNumber": 19462957,
        "network": 1,
        "srcToken": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        "srcDecimals": 6,
        "srcAmount": "1000000000",
        "destToken": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        "destDecimals": 18,
        "destAmount": "283341969876959340",
        "bestRoute": [
            {
                "percent": 100,
                "swaps": [
                    {
                        "srcToken": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                        "srcDecimals": 6,
                        "destToken": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                        "destDecimals": 18,
                        "swapExchanges": [
                            {
                                "exchange": "UniswapV3",
                                "srcAmount": "1000000000",
                                "destAmount": "283341969876959340",
                                "percent": 100,
                                "poolAddresses": [
                                    "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640"
                                ],
                                "data": {
                                    "path": [
                                        {
                                            "tokenIn": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                            "tokenOut": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
                                            "fee": "500",
                                            "currentFee": "500"
                                        }
                                    ],
                                    "gasUSD": "13.515820"
                                }
                            }
                        ]
                    }
                ]
            }
        ],
        "gasCostUSD": "14.656605",
        "gasCost": "118200",
        "side": "SELL",
        "version": "6.2",
        "contractAddress": "0x6a000f20005980200259b80c5102003040001068",
        "tokenTransferProxy": "0x6a000f20005980200259b80c5102003040001068",
        "contractMethod": "swapExactAmountInOnUniswapV3",
        "partnerFee": 0,
        "srcUSD": "999.4370000000",
        "destUSD": "1003.8267642998",
        "partner": "anon",
        "maxImpactReached": false,
        "hmac": "7975cda2fd343cb90f1a15d1ec11302c467a8d7d"
    }
}
```

{% endtab %}

{% tab title="400 Price Error" %}

```
{
  "error": "Validation failed with error"
  }
```

{% endtab %}
{% endtabs %}

#### Most common error messages

The following is a list of the most common error messages of the `/prices` endpoint. Most are self-explanatory and can be self-solved,  but feel free to contact Velora Support using the chat in the bottom right corner of this page.

* `Invalid route, from token should be the first token of the route`
* `Invalid route, to token should be the last token of the route`
* `Token not found. Please pass srcDecimals & destDecimals query params to trade any tokens` -Check the doc for more details <https://developers.paraswap.network/api/get-rate-for-a-token-pair>
* `Invalid tokens` - (srcToken and destToken) or (route) params are not passed
* `If receiver is defined userAddress should also be defined`
* `It is not allowed to pass both params: "positiveSlippageToUser" and "takeSurplus".` - We advice removing "positiveSlippageToUser", because it is deprecated
* `excludeDirectContractMethods param is deprecated, please use excludeContractMethodsWithoutFeeModel for newer versions`
* `Invalid Amount` - amount param is not a valid number
* `Validation failed: <error>` - params validation failed (message has the exact reason for failure)
* `Price Timeout` - reverts when a query takes more time than expected
* `No routes found with enough liquidity`&#x20;
* `Bad USD price` ![:large\_orange\_circle:](https://a.slack-edge.com/production-standard-emoji-assets/14.0/apple-medium/1f7e0.png) - src or dest tokens don’t have valid usd price&#x20;
* `Estimated_loss_greater_than_max_impact`
* `Internal Error while computing the price` - something went wrong during the price route calculation
* `Invalid max USD impact` - maxUSDImpact is not a valid number
* `Error while handling price request` - something went wrong during the price route calculation

\ <br>


# Build a transaction: /transactions

## Build Transaction

<mark style="color:green;">`POST`</mark> `https://api.paraswap.io/transactions/:network`

Build parameters for a transaction with the response from `/prices` endpoint.

#### Path Parameters

Path parameters define the network on which the transaction will be executed. Since blockchain networks operate independently, specifying the correct network ensures that the API queries the right environment for liquidity and transaction execution.

| Name    | Type   | Description                                                                                                                                                                    |
| ------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| network | number | Network ID. (Mainnet - 1, Optimism - 10, BSC - 56, Polygon - 137, Base - 8453, Arbitrum - 42161, Avalanche - 43114, Gnosis - 100, Sonic - 146, Unichain - 130, Plasma - 9745). |

#### Query Parameters

As an integrator, you can modify the behavior of the API call based on the Query parameters. This allows you to customize the response based on your needs.

| Name              | Type    | Description                                                                                                                                                                                                                                                                                                                                                                        |
| ----------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| gasPrice          | string  | Gas-price to be used for the transaction ***in wei***.                                                                                                                                                                                                                                                                                                                             |
| ignoreChecks      | boolean | <p>Allows the API to skip performing on-chain checks such as <em><strong>balances</strong></em>, <em><strong>allowances</strong></em>, as well as possible <em><strong>transaction failures</strong></em>. <br><strong>\*Note</strong>: The response does not contain <code>gas</code> parameter when <code>ignoreChecks</code> is set to true.<br>Default: <code>false</code></p> |
| ignoreGasEstimate | boolean | <p>Allows the API to skip gas checks <br><strong>\*Note</strong>: The response does not contain <code>gas</code> parameter when <code>ignoreGasEstimate</code> is set to true.<br>Default: <code>false</code></p>                                                                                                                                                                  |
| onlyParams        | boolean | <p>Allows the API to return the contract parameters only.<br>Default: <code>false</code></p>                                                                                                                                                                                                                                                                                       |
| eip1559           | boolean | <p>Allows the API to return EIP-1559 styled transaction with <code>maxFeePerGas</code> and <code>maxPriorityFeePerGas</code> paramters. </p><p>\*Note: We currently support EIP1559 transactions in the following chains:</p><p>Mainnet, Ropsten, and Avalanche.</p><p></p><p>Default: <code>false</code></p>                                                                      |

#### Request Body

The request body provides the details needed to execute a swap, including token details, amounts, pricing data, and user-specific parameters.

| Name                | Type    | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| srcToken            | string  | Destination Token Address. *Only Token Symbol could be speciﬁed for tokens from* `/tokens`.                                                                                                                                                                                                                                                                                                                                                                                                                     |
| srcDecimals         | integer | Source Token Decimals. (Can be omitted if Token Symbol is provided for `srcToken`).                                                                                                                                                                                                                                                                                                                                                                                                                             |
| destToken           | string  | Destination Token Address. *Only Token Symbol could be speciﬁed for tokens from* `/tokens`.                                                                                                                                                                                                                                                                                                                                                                                                                     |
| destDecimals        | integer | Destination Token Decimals. (Can be omitted if Token Symbol is provided for `destToken`).                                                                                                                                                                                                                                                                                                                                                                                                                       |
| srcAmount           | integer | Source Amount with decimals. Required if **side=SELL**. Could only be omitted if **slippage** is provided when **side=BUY**                                                                                                                                                                                                                                                                                                                                                                                     |
| destAmount          | integer | Destination amount with decimals. Required if **side=BUY**. Could only be omitted if **slippage** is provided when **side=SELL**.                                                                                                                                                                                                                                                                                                                                                                               |
| priceRoute          | object  | `priceRoute` from response body returned from `/prices` endpoint. `priceRoute` should be sent exactly as it was returned by the `/prices` endpoint.                                                                                                                                                                                                                                                                                                                                                             |
| slippage            | integer | <p>Allowed slippage percentage represented in basis points. <br><em>Eg:</em> for <strong>2.5%</strong> slippage, set the value to <strong>2.5 \* 100 = 250</strong>; for 10% = 1000. Slippage could be passed instead of <code>destAmount</code> when <strong>side=SELL</strong> or <code>srcAmount</code> when <strong>side=BUY</strong>. <br><code>Min: 0; Max: 10000</code></p>                                                                                                                              |
| userAddress         | string  | Address of the caller of the transaction (`msg.sender`)                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| txOrigin            | string  | Whenever `msg.sender` (userAddress) i.e. address calling the Velora contract is different than the address sending the transaction, `txOrigin` must be passed along with `userAddress`.                                                                                                                                                                                                                                                                                                                         |
| receiver            | string  | Address of the Receiver (that will receive the output of the swap). Used for Swap\&Transfer.                                                                                                                                                                                                                                                                                                                                                                                                                    |
| partnerAddress      | string  | <p>Address that will be entitled to claim fees or surplus.</p><p></p><p><em>\*Note: Fees have to be claimed from the</em> <a href="https://developers.paraswap.network/smart-contracts#fee-claimer"><em>Fee Claimer contract</em></a> <em>unless <code>isSurplusToUser</code> or <code>isDirectFeeTransfer</code>  are used</em></p>                                                                                                                                                                            |
| partnerFeeBps       | string  | <p>If provided it is used together with <code>partnerAddress</code>. Should be in basis points percentage. Look at <code>slippage</code> parameter description for understanding better.<br>Eg: <code>200</code> (for 2% fee percent)</p><p></p><p><em>\*Note: Fees have to be claimed from the</em> <a href="https://developers.paraswap.network/smart-contracts#fee-claimer"><em>Fee Claimer contract</em></a> <em>unless <code>isSurplusToUser</code> or <code>isDirectFeeTransfer</code>  are used</em></p> |
| partner             | string  | <p>Your <strong>project</strong> name.</p><p>Used for providing analytics on your <strong>project</strong> swaps.</p>                                                                                                                                                                                                                                                                                                                                                                                           |
| permit              | string  | Hex string for the signature used for Permit. This can be used to avoid giving approval. *Helps in saving gas.*                                                                                                                                                                                                                                                                                                                                                                                                 |
| deadline            | integer | <p>Timestamp (10 digit/seconds precision) <strong>till when the given transaction is valid</strong>. For a deadline of 5 minute, <em>deadline:</em> <code>Math.floor(Date.now()/1000) + 300</code><br><em>E.g.: 1629214486</em></p>                                                                                                                                                                                                                                                                             |
| isCapSurplus        | boolean | <p>Allows for capping the surplus at 1% maximum.</p><p>Default: <code>true</code></p>                                                                                                                                                                                                                                                                                                                                                                                                                           |
| takeSurplus         | boolean | <p>Allows to collect surplus. Works with <code>partnerAddress</code></p><p>Default: <code>false</code></p>                                                                                                                                                                                                                                                                                                                                                                                                      |
| isSurplusToUser     | boolean | <p>Specify if user should receive surplus instead of partner.<br>Default: <code>false</code></p>                                                                                                                                                                                                                                                                                                                                                                                                                |
| isDirectFeeTransfer | boolean | <p>Specify if fees should be sent directly to the partner instead of registering them on FeeClaimer.</p><p>Default: <code>false</code></p>                                                                                                                                                                                                                                                                                                                                                                      |

**Example:**

Here’s an example of a successful and failed transaction.

{% tabs %}
{% tab title="200 Transaction Request Response (When onlyParams=false)" %}

```
{
    "from": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
    "to": "0x6a000f20005980200259b80c5102003040001068",
    "value": "0",
    "data": "0xe3ead59e0000000000000000000000005f0000d4780a00d2dce0a00004000800cb0e5041000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000db4d11c67691ad50000000000000000000000000000000000000000000000000dd8426a4440caf10a8104c26c244959a1d46f205acc49520000000000000000000000000133fc2c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000160a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000004610ba8d5d10fba8c048a2051a0883ce04eabace00000000000000000000000000000000000000000000000000000000000f42406a000f20005980200259b80c51020030400010680000008000240000ff0600030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000f4240000000000000000000004de54610ba8d5d10fba8c048a2051a0883ce04eabace",
    "gasPrice": "16000000000",
    "chainId": 1
}
```

{% endtab %}

{% tab title="400 Transaction Building Error" %}

```
{
  "error": "Unable to process the transaction"
}
```

{% endtab %}
{% endtabs %}

#### Most common error messages

The following is a list of the most common error messages of the `/transactions` endpoint. Most are self-explanatory and can be self-solved,  but feel free to contact Velora Support using the chat in the bottom right corner of this page.

* `Validation failed: permit signature should be lower than 706`
* `Validation failed: <error>` - params validation failed (message has the exact reason of failure)
* `Missing price route` - price route param is not passed
* `Missing srcAmount` (sell)
* `Cannot specify both slippage and destAmount` (sell)
* `Missing slippage or destAmount` (sell)
* `Missing slippage or srcAmount` (buy)
* `Source Amount Mismatch` (sell)
* `Destination Amount Mismatch` (buy)
* `Missing destAmount` (buy)
* `Cannot specify both slippage and srcAmount` (buy)
* `Network Mismatch`
* `Source Token Mismatch`
* `Destination Token Mismatch`
* `Contract method doesn't support swap and transfer`
* `Side Mismatch`
* `Source Decimals Mismatch`
* `Destination Decimals Mismatch`
* `It is not allowed to pass both params: "positiveSlippageToUser" and "takeSurplus".` - We advise removing "positiveSlippageToUser" because it is deprecated
* `When "isSurplusToUser"="true", "takeSurplus" must be also "true" and either "partnerAddress" or "partner" must be set`
* `When "isDirectFeeTransfer"="true", please also set "takeSurplus"="true" and provide partner/fee information via "partnerFeeBps" & "partnerAddress" or valid "partner" params; or add "referrer" param`
* `Internal Error while building transaction` - something went wrong during the transaction build
* `Unable to build transaction <code>` -  something went wrong during the transaction build
* `It is not allowed to have limit-orders Dex or paraswappool Dex in route and 'ignoreChecks=true' together. Consider requesting the price with excluded limit-orders if you want to use 'ignoreChecks': &excludeDEXS=ParaSwapPool,ParaSwapLimitOrders`
* `It seems like the rate has changed, please re-query the latest Price`
* `The rate has changed, please re-query the latest Price`
* `This transaction has some errors and may fail. Please contact support for more details`
* `Not enough <token> balance`
* `Not enough <token> allowance given to TokenTransferProxy(<spender>)`
* `Unable to check price impact` - src or dest tokens don’t have valid usd price&#x20;



# Example: Fetch Price & Build Transaction

Here’s an example of an implementation for Velora's Market API. It utilizes Velora's endpoints to fetch pricing information and build transactions for token swaps.

{% tabs %}
{% tab title="API" %}
{% embed url="<https://gist.github.com/Velenir/64f6449e4461cf965ea5a18941a330f9>" %}

{% endtab %}

{% tab title="SDK" %}
{% embed url="<https://gist.github.com/Velenir/a9b0b1a1958ad9e2fe6543d596320743>" %}

{% endtab %}
{% endtabs %}

{% embed url="<https://codesandbox.io/p/sandbox/still-violet-zhtgzh>" %}

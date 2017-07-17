# Pump and Dump Bot for Bittrex Exchange

![Screen Shot 2017-07-17 at 7.32.51 PM.png](https://steemitimages.com/DQmRQZMoNbWa5xfWZcUdBPTam1jcs65vuWGdo7agg1Xqx5w/Screen%20Shot%202017-07-17%20at%207.32.51%20PM.png)

#Steps to Setup the Bot:

* Go to Bittrex Settings Tab, You need to generate API key to Place BUY or SELL order via Bot. Under API Keys in sidebar :
1. Click on Add New Key
2. Make *Read Info*, *Trade Limit*, *Trade Market* - ON. **Remember not to give Withdraw permission to your bot**
3. Put you 2-Factor Authentication Code
4. Click Update Keys

Now, you will get **KEY** and **SECRET**, Copy them and Store it at safe place as **SECRET** will vanish once page refreshes.

![Screen Shot 2017-07-17 at 1.30.21 PM.png](https://steemitimages.com/DQmTb8v4ygvqdai46CWuFNVUsDQ3ye4MrBVfd6qzxwVPArH/Screen%20Shot%202017-07-17%20at%201.30.21%20PM.png)

**Pre-requisites:**

* Git (optional if you don't want to contribute, just download  the repo from github)
* Install **Ruby** on your machine as script is written in ruby language.


* Go To my Github Repo, Download/ Clone It: [pump and dump bot](https://github.com/aqfaridi/pump_and_dump_bot)
   `git clone git@github.com:aqfaridi/pump_and_dump_bot.git`

* Navigate to the folder in your local machine, Edit **API_KEY** and **API_SECRET** in **bittrex_bot.rb** with your KEY and SECRET as generated above.

  ```
  API_KEY = "<YOUR_API_KEY>"
  API_SECRET = "<YOUR_API_SECRET>"
  ```

* Run the **bot script** using following command in terminal/ command prompt: 

```
ruby bittrex_bot.rb "COIN_CODE", "BOT_TYPE"
```

There are seven types of BOT as follows: 

1. **BUY BOT** which purchase the coin, taking care of coin not being prepumped, BOT_TYPE=1
      e.g For Siacoin(SC), Run like this : `ruby bittrex_bot.rb "SC" "1"`

2. **SELL BOT** which place sell order at given percent decrease as compared to last price of the market , BOT_TYPE=2
      e.g For Siacoin(SC), Run like this : `ruby bittrex_bot.rb "SC" "2"`

3. **BUY_AND_SELL BOT** which purchase the coin at minimum price and place the sell order at increment profits, BOT_TYPE=3
      e.g For Siacoin(SC), Run like this : `ruby bittrex_bot.rb "SC" "3"`

4. **SELL_AT_ANY_COST BOT** which cancel all the open orders and sell the coin at breakeven or in loss to make an exit from the pump in case of unexpected scenario, BOT_TYPE=4
     e.g For Siacoin(SC), Run like this : `ruby bittrex_bot.rb "SC" "4"`

5. **BUY_ALL BOT** which purchases all the low volume ( < 50) coins on Bittrex, taking care of coin not being prepumped, BOT_TYPE=5
      e.g For Siacoin(SC), Run like this : `ruby bittrex_bot.rb "OPTIONAL" "5"`

6. **SELL_ALL BOT** which place sell orders against all low volume coins purchased by BOT-5 at given profit( by default **20%**) , BOT_TYPE=6
      e.g For Siacoin(SC), Run like this : `ruby bittrex_bot.rb "OPTIONAL" "6"`

7. **CANCEL_ALL BOT** which cancel all open orders across all BTC cryptocurrency pairs on Bittrex, BOT_TYPE=7
     e.g For Siacoin(SC), Run like this : `ruby bittrex_bot.rb "OPTIONAL" "7"`

**Tuning of Parameters in Bot Script:**

1. Open **bittrex_bot.rb**, navigate to the end of file :  Change these lines according to the instructions below => 

```
buy_bot(0.05, 0.006, 0.5) if BOT_TYPE == 1
sell_order = sell_bot(0.1) if BOT_TYPE == 2
buy_sell_bot(0.05, 0.012, 0.5, 0.1, 2) if BOT_TYPE == 3
sell_at_any_cost(0.3) if BOT_TYPE == 4
buy_all_bot(0.05, 0.006, 0.5) if BOT_TYPE == 5
sell_all_bot(0.2) if BOT_TYPE == 6
cancel_all_bot if BOT_TYPE == 7
```



> **BUY BOT** has three parameters:


```
# method to place BUY order
# params: 
# percent_increase(float) - BUY price will be percent_increase of last_price of the market i.e BUY_PRICE = (1.0 + percent_increase)*last_price
# chunk(float) - Amount of BTC to invest for buying altcoin i.e BUY IF [last_price < (1.0 + prepump_buffer)*low_24_hr]
# prepump_buffer(float) -  Allowed buffer for prepump
def buy_bot(percent_increase = 0.05, chunk = 0.006, prepump_buffer = 0.5)
```

* You can pass values as per the need, for example :

`buy_bot(0.05, 0.01, 0.5) if BOT_TYPE == 0`  means you want to purchase coin with **5%** increase of the last price of the market with **0.01 BTC** having *prepump_buffer* of **50%** meaning if coin is prepumped more than **50%** of the last 24-hour low then you won't buy. 

> **SELL BOT** has one parameter:

```
# method to place SELL order
# params:
# percent_decrease(float) - BUY price will be percent_decrease of last_price of the market, eg. SELL_PRICE = (1.0 - percent_decrease)*last_price
def sell_bot(percent_decrease = 0.1)
```

* Change *percent_decrease* as per the need : 

`sell_order = sell_bot(0.1) if BOT_TYPE == 2` means you want to sell all the available coins with **10%** decrease of the last price of the market.


> **BUY_AND_SELL BOT** has five parameters:

```
# method to place BUY and SELL order immediately after purchase
# params :
# percent_increase(float)  ->  BUY_PRICE = (1.0 + percent_increase) * last_price
# chunk(float)  -> Amount of BTC to invest for buying altcoin
# prepump_buffer(float) -  Allowed buffer for prepump
# profit(float) -> SELL_PRICE = (1.0 + profit) * BUY_PRICE
# splits(int) -> How many splits of available quantity you want to make [profit] increment each time in next sell order
def buy_sell_bot(percent_increase = 0.05, chunk = 0.004, prepump_buffer = 0.5, profit = 0.2, splits = 2)

```
* You can pass values as per the need, for example :

`buy_sell_bot(0.05, 0.012, 0.5, 0.1, 2) if BOT_TYPE == 3` means you want to purchase coin with **5%** increase of the last price of the market with **0.012 BTC** having *prepump_buffer* of **50%** meaning if coin is prepumped more than **50%** of the last 24-hour low then you won't buy. Immediately, 2(splits) Sell orders will be placed with **10%** profit of the buy price in first order, next sell order will be placed with **20%** profit in incremental manner based on number of *splits*.

You can change the number of sell order by passing **splits** (last parameter), but remember **0.005 BTC** is the minimum amount required to place a sell order i.e if you keep *splits* as 10 then you need to invest **0.05 BTC** as *chunk*.


> **SELL_AT_ANY_COST BOT** has one parameter:

```
# method to place SELL order by cancelling all open orders
# params:
# percent_decrease(float) - BUY price will be percent_decrease of last_price of the market, eg. SELL_PRICE = (1.0 - percent_decrease)*last_price
def sell_at_any_cost(percent_decrease)
```
* Change *percent_decrease* as per the need : 

`sell_at_any_cost(0.3) if BOT_TYPE == 4` means you want to cancel all open orders and place one sell order at **30%** decrease of the last traded price of the market.

> **BUY_ALL BOT** has same parameters as that of **BUY BOT**.

> **SELL_ALL BOT** has one parameter: 
```
# method to sell all BTC pair orders on bittrex
# params- profit_rate(float)[default = 0.2] at which sell orders need to be set
def sell_all_bot(profit_rate = 0.2)
```
* Change *profit_rate* as per the need : 

`sell_all_bot(0.2) if BOT_TYPE == 6` means you want to place sell orders with **20%** profit on the net purchased value

> **CANCEL_ALL BOT** has no parameters as its task is only to cancel all open orders.


**Must Read :**

[Beware Crypto Traders !! Pump & Dump Group on Telegram](https://steemit.com/cryptocurrency/@aqfaridi/beware-crypto-traders-pump-and-dump-group-on-telegram)

[Don't Panic: soft fork or hard fork is good for Bitcoin !!](https://steemit.com/bitcoin/@aqfaridi/don-t-panic-just-hodl-august-1-soft-fork-or-hard-fork-is-good-for-bitcoin)

**Possible Strategies:**

1. Run **BUY Bot** and then go to Bittrex Trading page, Watch BIDs and ASKs, once you realise that momentum is decreasing, Run **SELL Bot** at that moment which will book your profit.  - *This strategy requires manual intervention*

2. Run **BUY_AND_SELL Bot** and then go to Bittex Trading page, Watch if your sell orders got executed or not, If not and momentum is decreasing then Run **SELL_AT_ANY_COST Bot**, If Yes then you already made your profit :)

3. Run **BUY_ALL Bot** and then Run **SELL_ALL Bot** at given profit, No need to monitor, once a coin being pumped or attain let say 20% gain, sell order will be executed automatically. [*For changing the profit of **SELL_ALL Bot**, Run **CANCEL_ALL Bot**, and then again  Run **SELL_ALL Bot** with different profit*]

**Future Scope:**

* Extending it detect pump or momentum in the crypto pair.
* Take trade entry / exit on the basis of RSI/MACD/OBV indicators, Run it as Cron job on the server to automate the process.

**DON'T FORGET TO MAKE DONATIONS IF YOU FIND IT HELPFUL OR MAKE PROFITS OUT OF IT:**

```
Bitcoin(BTC) Address : 1B4Q5yPHaGDRSfGqzyZj3EevQhP2yAm2Te
Ethereum(ETH) Address : 0xb2fff53651b1335f195361601a44118f7ee1f46a
Litcoin(LTC) Address : LiVuQjBwMhoaf7QLuVGBgx9g8TPYSgcrmx
```

Join My Channel at Telegram : [Crypto Trading Technical Analysis](https://t.me/crypto_tech_analysis)


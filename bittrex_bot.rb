require "rest-client"
require "colorize"
require "json"
BASE_URL = "https://bittrex.com/api/v1.1/"
API_KEY = "<YOUR_API_KEY>"
API_SECRET = "<YOUR_API_SECRET>"
@units_bought = 0
@currency = ARGV[0]
@market_name = "BTC-"+@currency
BOT_TYPE = ARGV[1].to_i
URIs = {
        :public => {
          :markets => "public/getmarkets",
          :currencies => "public/getcurrencies",
          :market_ticker => "public/getticker?market=%s",
          :market_day_summaries => "public/getmarketsummaries",
          :market_day_summary => "public/getmarketsummary?market=%s",
          :order_book => "public/getorderbook?market=%s&type=%s&depth=%s",
          :last_trades => "public/getmarkethistory?market=%s",
        },
        :account => {
          :balance => "account/getbalances",
          :currency_balance => "account/getbalance?currency=%s",
          :deposit_address => "account/getdepositaddress?currency=%s",
          :withdraw => "account/withdraw?currency=%s&quantity=%s&address=%s",    
          :get_order_by_uuid => "account/getorder&uuid=%s",
          :orders_history => "account/getorderhistory",
          :market_orders_history => "account/getorderhistory?market=%s",
          :withdrawal_history => "account/getwithdrawalhistory?currency=%s",
          :deposit_history => "account/getwithdrawalhistory?currency=%s"
        },
        :market => {
          :buy => "market/buylimit?market=%s&quantity=%s&rate=%s",
          :sell => "market/selllimit?market=%s&quantity=%s&rate=%s",
          :cancel_by_uuid => "market/cancel?uuid=%s",
          :open_orders => "market/getopenorders?market=%s"
        }
      }

def hmac_sha256(msg, key)
  digest = OpenSSL::Digest.new("sha512")
  OpenSSL::HMAC.hexdigest(digest, key, msg)
end

def get_url(params)
  url = BASE_URL + URIs[params[:api_type].to_sym][params[:action].to_sym]
  case params[:action]
  when "buy"
    url = sprintf(url, params[:market], params[:quantity], params[:rate])
  when "sell"
    url = sprintf(url, params[:market], params[:quantity], params[:rate])
  when "cancel_by_uuid"
    url = sprintf(url, params[:uuid])
  when "open_orders", "getticker", "market_day_summary", "last_trades", "market_orders_history"
    url = sprintf(url, params[:market])
  when "currency_balance", "deposit_address"
    url = sprintf(url, params[:currency])
  when "order_book"
    url = sprintf(url, params[:market], params[:order_type], params[:depth])
  end
  nonce = Time.now.to_i.to_s
  url = url + "&apikey=#{API_KEY}&nonce=#{nonce}" if ["market", "account"].include? params[:api_type]
  return url
end

def call_api(url)
  response = RestClient.get(url)
  parsed_body = JSON.parse(response.body)
  puts "Fetching Market Summary...".yellow
  p [url, parsed_body]
  puts (parsed_body["success"] ? "Success".green : "Failed".red)
  parsed_body["result"] if parsed_body["success"]
end

def call_secret_api(url)
  sign = hmac_sha256(url, API_SECRET)
  response = RestClient.get(url, {:apisign => sign})
  puts "Calling API...".yellow
  parsed_body = JSON.parse(response.body)
  p [url, parsed_body]
  puts (parsed_body["success"] ? "Success".green : "Failed".red)
  parsed_body["result"] if parsed_body["success"]
end

# method to cancel all open BTC pair orders on bittrex
def cancel_all_bot
  markets_url = get_url({:api_type => "public", :action => "markets"})
  markets = call_api(markets_url)
  markets.each do |market|
    currency = market["MarketCurrency"]
    base_currency = market["BaseCurrency"]
    market_name = market["MarketName"]
    if market["IsActive"] and base_currency == "BTC"
      open_orders_url = get_url({:api_type => "market", :action => "open_orders", :market => market_name})
      open_orders = call_secret_api(open_orders_url)
      if open_orders.size > 0
        p [market_name, open_orders]
        open_orders.each do |open_order|
          cancel_order_url = get_url({:api_type => "market", :action => "cancel_by_uuid", :uuid => open_order["OrderUuid"]})
          order = call_secret_api(cancel_order_url)
        end
        p ["Orders cancelled for #{market_name}"]
      end
    end
  end
end

# method to sell all BTC pair orders on bittrex
# params- profit_rate(float)[default = 0.2] at which sell orders need to be set
def sell_all_bot(profit_rate = 0.2)
  markets_url = get_url({:api_type => "public", :action => "markets"})
  markets = call_api(markets_url)
  expected_worth = 0.0
  markets.each do |market|
    currency = market["MarketCurrency"]
    base_currency = market["BaseCurrency"]
    market_name = market["MarketName"]
    if market["IsActive"] and base_currency == "BTC"
      get_balance_url = get_url({:api_type => "account", :action => "currency_balance", :currency => currency})
      balance_details = call_secret_api(get_balance_url)
      if balance_details["Available"] and balance_details["Available"] > 0.0 #purchased coins
        orders_history_url = get_url({:api_type => "account", :action => "market_orders_history", :market => market_name})
        orders_history = call_secret_api(orders_history_url)
        net_value = 0.0
        orders_history.each do |order|
          net_value += order["Price"] if order["OrderType"] == "LIMIT_BUY"
          net_value -= order["Price"] if order["OrderType"] == "LIMIT_SELL"
        end
        if net_value > 0 # buys are more, we need to get more than this net value by selling available coins
          sell_price = (net_value + net_value*profit_rate)/balance_details["Available"]
          sell_price = "%.8f" % sell_price
          sell_limit_url = get_url({:api_type => "market", :action => "sell", :market => market_name, :quantity => balance_details["Available"], :rate => sell_price})
          order_placed = call_secret_api(sell_limit_url)
          p [order_placed, "for #{market_name} at #{sell_price}"]
        end
        expected_worth += (net_value + net_value*profit_rate)
      end
    end
  end
  p ["Expected Worth=", expected_worth]
end

def get_market_summary(market_name)
  market_summary_url = get_url({:api_type => "public", :action => "market_day_summary", :market => market_name})
  summary = call_api(market_summary_url).first
  low_24_hr, last_price, ask_price, volume = summary["Low"], summary["Last"], summary["Ask"], summary["BaseVolume"]
  [low_24_hr, last_price, ask_price, volume]
end

def buy_chunk(last_price, market_name, percent_increase, chunk)
  unit_price = last_price + last_price * percent_increase
  quantity = chunk/unit_price
  buy_limit_url = get_url({:api_type => "market", :action => "buy", :market => market_name, :quantity => quantity, :rate => unit_price})
  puts "Purchasing coin...".yellow
  p [{:api_type => "market", :action => "buy", :market => market_name, :quantity => quantity, :rate => unit_price}]
  order = call_secret_api(buy_limit_url)
  puts ((order and !order["uuid"].nil?) ? "Success".green : "Failed".red)
  cnt = 1
  while cnt <= 3 and order and order["uuid"].nil? #retry
    puts "Retry #{cnt}: Purchasing coin...".yellow
    sleep(1) # half second
    order = call_secret_api(buy_limit_url)
    puts ((order and !order["uuid"].nil?) ? "Success".green : "Failed".red)
    cnt += 1
  end
  @units_bought = quantity if order and !order["uuid"].nil?
  order
end

# method to place BUY order
# params: 
# percent_increase(float) - BUY price will be percent_increase of last_price of the market i.e BUY_PRICE = (1.0 + percent_increase)*last_price
# chunk(float) - Amount of BTC to invest for buying altcoin i.e BUY IF [last_price < (1.0 + prepump_buffer)*low_24_hr]
# prepump_buffer(float) -  Allowed buffer for prepump
def buy_bot(percent_increase = 0.05, chunk = 0.006, prepump_buffer = 0.5)
  market_name = @market_name
  low_24_hr, last_price, ask_price, volume = get_market_summary(market_name)
  total_spent = 0.0
  p [low_24_hr, last_price, ask_price, volume]
  if volume < 100 and last_price < (1.0 + prepump_buffer) * low_24_hr #last_price is smaller than 50% increase since yerterday
    puts "Coin is not prepumped".blue
    order = buy_chunk(last_price, market_name, percent_increase, chunk)
    p [order, "Units Bought : #{@units_bought}"]
  end
end

# method to BUY all low volume coins
# params: 
# percent_increase(float) - BUY price will be percent_increase of last_price of the market i.e BUY_PRICE = (1.0 + percent_increase)*last_price
# chunk(float) - Amount of BTC to invest for buying altcoin i.e BUY IF [last_price < (1.0 + prepump_buffer)*low_24_hr]
# prepump_buffer(float) -  Allowed buffer for prepump
def buy_all_bot(percent_increase = 0.05, chunk = 0.006, prepump_buffer = 0.5)
  markets_url = get_url({:api_type => "public", :action => "markets"})
  markets = call_api(markets_url)
  markets.each do |market|
    currency = market["MarketCurrency"]
    base_currency = market["BaseCurrency"]
    market_name = market["MarketName"]
    if market["IsActive"] and base_currency == "BTC"
      @market_name = market_name
      buy_bot(percent_increase, chunk, prepump_buffer)
    end
  end
end


# method to place SELL order
# params:
# percent_decrease(float) - BUY price will be percent_decrease of last_price of the market, eg. SELL_PRICE = (1.0 - percent_decrease)*last_price
def sell_bot(percent_decrease = 0.1)
  market_name = @market_name
  currency = @currency
  low_24_hr, last_price, ask_price = get_market_summary(market_name)
  sell_price = last_price - percent_decrease*last_price
  get_balance_url = get_url({:api_type => "account", :action => "currency_balance", :currency => currency})
  balance_details = call_secret_api(get_balance_url)
  sell_price = "%.8f" % sell_price
  if balance_details and balance_details["Available"] and balance_details["Available"] > 0.0
    p [market_name, last_price, balance_details["Available"], sell_price]
    sell_limit_url = get_url({:api_type => "market", :action => "sell", :market => market_name, :quantity => balance_details["Available"], :rate => sell_price})
    puts "Selling coin...".yellow
    p [{:api_type => "market", :action => "sell", :market => market_name, :quantity => balance_details["Available"], :rate => sell_price}]
    order_placed = call_secret_api(sell_limit_url)
    puts (order_placed and !order_placed["uuid"].nil? ? "Success".green : "Failed".red)
    cnt = 1
    while cnt <= 3 and order_placed and order_placed["uuid"].nil? #retry
      puts "Retry #{cnt} : Selling coin...".yellow
      sleep(1) # half second
      order_placed = call_secret_api(sell_limit_url)
      puts (order_placed and !order_placed["uuid"].nil? ? "Success".green : "Failed".red)
      cnt += 1
    end
    p [order_placed, "Sell #{balance_details["Available"]} of #{market_name} at #{sell_price}"]
  else
    puts "Insufficient Balance".red
  end
end

# method to place BUY and SELL order immediately after purchase
# params :
# percent_increase(float)  ->  BUY_PRICE = (1.0 + percent_increase) * last_price
# chunk(float)  -> Amount of BTC to invest for buying altcoin
# prepump_buffer(float) -  Allowed buffer for prepump
# profit(float) -> SELL_PRICE = (1.0 + profit) * BUY_PRICE
# splits(int) -> How many splits of available quantity you want to make [profit] increment each time in next sell order
def buy_sell_bot(percent_increase = 0.05, chunk = 0.004, prepump_buffer = 0.5, profit = 0.2, splits = 2, no_of_retries = 10)
  market_name = @market_name
  currency = @currency
  low_24_hr, last_price, ask_price = get_market_summary(market_name)
  total_spent = 0.0
  p [low_24_hr, last_price, ask_price]
  if last_price < (1.0 + prepump_buffer)*low_24_hr #last_price is smaller than 50% increase since yerterday
    order = buy_chunk(last_price, market_name, percent_increase, chunk)
    buy_price = last_price + last_price * percent_increase
    counter = 0
    while counter < no_of_retries
      get_balance_url = get_url({:api_type => "account", :action => "currency_balance", :currency => currency})
      balance_details = call_secret_api(get_balance_url)
      p balance_details
      if balance_details and balance_details["Available"] and balance_details["Available"] > 0.0 # available coins present
        qty = balance_details["Available"]/splits
        splits.times do |i|
          qty += (balance_details["Available"].to_i % splits) if (i-1 == splits)
          sell_price = buy_price + buy_price * (profit * (i+1))
          sell_price = "%.8f" % sell_price
          sell_limit_url = get_url({:api_type => "market", :action => "sell", :market => market_name, :quantity => qty, :rate => sell_price})
          puts "Selling coin...".yellow
          p [{:api_type => "market", :action => "sell", :market => market_name, :quantity => qty, :rate => sell_price}]
          order_placed = call_secret_api(sell_limit_url)
          puts (order_placed and !order_placed["uuid"].nil? ? "Success".green : "Failed".red)
          cnt = 1
          while cnt <= 3 and order_placed and order_placed["uuid"].nil? #retry
            puts "Retry #{cnt} : Selling coin...".yellow
            sleep(1) # half second
            order_placed = call_secret_api(sell_limit_url)
            puts (order_placed and !order_placed["uuid"].nil? ? "Success".green : "Failed".red)
            cnt += 1
          end
          p [order_placed, "Sell #{qty} of #{market_name} at #{sell_price}"]
        end
        break
      end
      counter += 1
      sleep(0.5)
    end
  end
end

# method to place SELL order by cancelling all open orders
# params:
# percent_decrease(float) - BUY price will be percent_decrease of last_price of the market, eg. SELL_PRICE = (1.0 - percent_decrease)*last_price
def sell_at_any_cost(percent_decrease = 0.3)
  market_name = @market_name
  open_orders_url = get_url({:api_type => "market", :action => "open_orders", :market => market_name})
  open_orders = call_secret_api(open_orders_url)
  #cancel all orders
  if open_orders.size > 0
    open_orders.each do |open_order|
      cancel_order_url = get_url({:api_type => "market", :action => "cancel_by_uuid", :uuid => open_order["OrderUuid"]})
      call_secret_api(cancel_order_url)
    end
  end
  # call sell bot again with lower profit
  sell_order = sell_bot(percent_decrease)
end

buy_bot(0.05, 0.006, 0.5) if BOT_TYPE == 1
sell_order = sell_bot(0.1) if BOT_TYPE == 2
buy_sell_bot(0.05, 0.012, 0.5, 0.1, 2) if BOT_TYPE == 3
sell_at_any_cost(0.3) if BOT_TYPE == 4
buy_all_bot(0.05, 0.006, 0.5) if BOT_TYPE == 5
sell_all_bot(0.2) if BOT_TYPE == 6
cancel_all_bot if BOT_TYPE == 7


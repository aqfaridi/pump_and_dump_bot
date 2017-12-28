require "rest-client"
require "colorize"
require "json"
require "cgi"
require 'open-uri'
BASE_URL = "https://yobit.net/"
API_KEY = "API_KEY"
API_SECRET = "API_SECRET"
@units_bought = 0
@currency = ARGV[0].downcase
@market_name = @currency+"_btc"
BOT_TYPE = ARGV[1].to_i
URIs = {
        :public => {
          :ticker => "api/3/ticker/%s",
          :market_day_summary => "api/3/ticker/%s",
          :order_book => "api/3/depth/%s",
          :last_trades => "api/3/trades/%s",
        },
        :account => {
          :balance => "tapi?method=getInfo",
        },
        :market => {
          :buy => "tapi?pair=%s&type=buy&rate=%s&amount=%s&method=Trade",
          :sell => "tapi?pair=%s&type=sell&rate=%s&amount=%s&method=Trade",
          :cancel_by_uuid => "tapi?order_id=%s&method=CancelOrder",
          :open_orders => "tapi?pair=%s&method=ActiveOrders"
        }
      }
def hmac_sha256(msg, key)
  p URI::encode(msg)
  digest = OpenSSL::Digest.new("sha512")
  OpenSSL::HMAC.hexdigest(digest, key, URI::encode(msg))
end

def get_url(params)
  url = BASE_URL + URIs[params[:api_type].to_sym][params[:action].to_sym]
  case params[:action]
  when "buy"
    url = sprintf(url, params[:market], params[:rate], params[:quantity])
  when "sell"
    url = sprintf(url, params[:market], params[:rate], params[:quantity])
  when "cancel_by_uuid"
    url = sprintf(url, params[:order_id])
  when "open_orders", "market_day_summary", "last_trades"
    url = sprintf(url, params[:market])
  when "order_book"
    url = sprintf(url, params[:market])
  end
  nonce = Time.now.to_i.to_s
  url = url + "&nonce=#{nonce}" if ["market", "account"].include? params[:api_type]
  return url
end

def call_api(url)
  p url
  response = RestClient.get(url)
  parsed_body = JSON.parse(response.body)
  puts "Fetching Market Summary...".yellow
  p [url, parsed_body]
  puts (parsed_body["#{@market_name}"] ? "Success".green : "Failed".red)
  parsed_body["#{@market_name}"] if parsed_body["#{@market_name}"]
end

def call_secret_api(url)
  params = (url.split("?").size == 2) ? url.split("?")[1] : ""
  sign = hmac_sha256(params, API_SECRET)
  api_endpoint = url.split("?")[0]
  payload = url.split("?")[1]
  params = {}
  payload.split("&").each do |arg|
    k, v = arg.split("=")
    params[k.to_s] = v.to_s
  end
  response = RestClient.post(api_endpoint, params, {:Key => API_KEY, :Sign => sign, 'User-Agent'=> "Mozilla/5.0", "Content-Type" => "application/x-www-form-urlencoded"})
  puts "Calling API...".yellow
  parsed_body = JSON.parse(response.body)
  p [url, parsed_body]
  puts (parsed_body["success"] ? "Success".green : "Failed".red)
  parsed_body["return"] if parsed_body["success"]
end

def get_market_summary(market_name)
  market_summary_url = get_url({:api_type => "public", :action => "market_day_summary", :market => market_name})
  summary = call_api(market_summary_url)
  low_24_hr, last_price, ask_price, volume = summary["low"], summary["last"], summary["sell"], summary["vol"]
  [low_24_hr, last_price, ask_price, volume]
end

def buy_chunk(last_price, market_name, percent_increase, chunk)
  unit_price = last_price + last_price * percent_increase
  quantity = chunk/unit_price
  unit_price = "%.8f" % unit_price
  buy_limit_url = get_url({:api_type => "market", :action => "buy", :market => market_name, :quantity => quantity, :rate => unit_price})
  puts "Purchasing coin...".yellow
  p [{:api_type => "market", :action => "buy", :market => market_name, :quantity => quantity, :rate => unit_price}]
  order = call_secret_api(buy_limit_url)
  puts ((order and !order["order_id"].nil?) ? "Success".green : "Failed".red)
  cnt = 1
  while cnt <= 3 and order and order["order_id"].nil? #retry
    puts "Retry #{cnt}: Purchasing coin...".yellow
    sleep(1) # half second
    order = call_secret_api(buy_limit_url)
    puts ((order and !order["order_id"].nil?) ? "Success".green : "Failed".red)
    cnt += 1
  end
  @units_bought = quantity if order and !order["order_id"].nil?
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

# method to place SELL order
# params:
# percent_decrease(float) - BUY price will be percent_decrease of last_price of the market, eg. SELL_PRICE = (1.0 - percent_decrease)*last_price
def sell_bot(percent_decrease = 0.1)
  market_name = @market_name
  currency = @currency
  low_24_hr, last_price, ask_price = get_market_summary(market_name)
  sell_price = last_price - percent_decrease*last_price
  get_balance_url = get_url({:api_type => "account", :action => "balance"})
  balance_details = call_secret_api(get_balance_url)
  sell_price = "%.8f" % sell_price
  if balance_details and balance_details["funds"] and balance_details["funds"][currency] and balance_details["funds"][currency] > 0.0
    p [market_name, last_price, balance_details["funds"][currency], sell_price]
    sell_limit_url = get_url({:api_type => "market", :action => "sell", :market => market_name, :quantity => balance_details["funds"][currency], :rate => sell_price})
    puts "Selling coin...".yellow
    p [{:api_type => "market", :action => "sell", :market => market_name, :quantity => balance_details["funds"][currency], :rate => sell_price}]
    order_placed = call_secret_api(sell_limit_url)
    puts (order_placed and !order_placed["order_id"].nil? ? "Success".green : "Failed".red)
    cnt = 1
    while cnt <= 3 and order_placed and order_placed["order_id"].nil? #retry
      puts "Retry #{cnt} : Selling coin...".yellow
      sleep(1) # half second
      order_placed = call_secret_api(sell_limit_url)
      puts (order_placed and !order_placed["order_id"].nil? ? "Success".green : "Failed".red)
      cnt += 1
    end
    p [order_placed, "Sell #{balance_details["funds"][currency]} of #{market_name} at #{sell_price}"]
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
def buy_sell_bot(percent_increase = 0.05, chunk = 0.004, prepump_buffer = 0.5, profit = 0.2, splits = 2)
  market_name = @market_name
  currency = @currency
  low_24_hr, last_price, ask_price = get_market_summary(market_name)
  total_spent = 0.0
  p [low_24_hr, last_price, ask_price]
  if last_price < (1.0 + prepump_buffer)*low_24_hr #last_price is smaller than 50% increase since yerterday
    order = buy_chunk(last_price, market_name, percent_increase, chunk)
    buy_price = last_price + last_price * percent_increase
    get_balance_url = get_url({:api_type => "account", :action => "balance"})
    balance_details = call_secret_api(get_balance_url)
    p balance_details
    if balance_details and balance_details["funds"][currency] and balance_details["funds"][currency] > 0.0 # available coins present
      qty = balance_details["funds"][currency]/splits
      splits.times do |i|
        qty += (balance_details["funds"][currency].to_i % splits) if (i-1 == splits)
        sell_price = buy_price + buy_price * (profit * (i+1))
        sell_price = "%.8f" % sell_price
        sell_limit_url = get_url({:api_type => "market", :action => "sell", :market => market_name, :quantity => qty, :rate => sell_price})
        puts "Selling coin...".yellow
        p [{:api_type => "market", :action => "sell", :market => market_name, :quantity => qty, :rate => sell_price}]
        order_placed = call_secret_api(sell_limit_url)
        puts (order_placed and !order_placed["order_id"].nil? ? "Success".green : "Failed".red)
        cnt = 1
        while cnt <= 3 and order_placed and order_placed["order_id"].nil? #retry
          puts "Retry #{cnt} : Selling coin...".yellow
          sleep(1) # half second
          order_placed = call_secret_api(sell_limit_url)
          puts (order_placed and !order_placed["order_id"].nil? ? "Success".green : "Failed".red)
          cnt += 1
        end
        p [order_placed, "Sell #{qty} of #{market_name} at #{sell_price}"]
      end
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
  p open_orders
  #cancel all orders
  if open_orders and open_orders.size > 0
    open_orders.each do |order_id, open_order|
      cancel_order_url = get_url({:api_type => "market", :action => "cancel_by_uuid", :order_id => order_id})
      call_secret_api(cancel_order_url)
    end
  end
  # call sell bot again with lower profit
  sell_order = sell_bot(percent_decrease)
end

buy_bot(0.05, 0.00011, 0.5) if BOT_TYPE == 1
sell_order = sell_bot(0.1) if BOT_TYPE == 2
buy_sell_bot(0.05, 0.0002, 0.5, 0.1, 1) if BOT_TYPE == 3
sell_at_any_cost(0.01) if BOT_TYPE == 4

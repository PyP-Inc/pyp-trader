//+------------------------------------------------------------------+
//|                                                       PyP EA.mq4 |
//|                                          PyP Trading Platform    |
//|                                    https://pyp.stanlink.online   |
//+------------------------------------------------------------------+
#property copyright "PyP Trading Platform"
#property link      "https://pyp.stanlink.online"
#property version   "2.00"
#property strict

//--- Inputs
input string EAToken           = "";       // EA Token (from PyP dashboard)
input string ApiUrl            = "https://api.pyp.stanlink.online"; // API URL
input bool   EnableTrading     = true;     // Enable Auto Trading

//--- Risk Management (0 = use server-calculated value)
input double ManualLotSize     = 0;        // Lot Size (0 = server calculates)
input double ManualSL_Pips     = 0;        // Stop Loss in pips (0 = server calculates)
input double ManualTP_Pips     = 0;        // Take Profit in pips (0 = server calculates)
input double MinConfidence     = 0.0;      // Min confidence to trade (0.0 = accept all)

//--- Order Settings
input int    MagicNumber       = 20260101; // Magic Number
input int    Slippage          = 3;        // Slippage (points)
input bool   CloseOnReverse    = true;     // Close opposite on reverse signal

//--- Internal state
datetime lastSignalTime = 0;

//+------------------------------------------------------------------+
int OnInit() {
   if (EAToken == "") {
      Alert("PyP EA: EAToken is required. Get it from your PyP dashboard → Deployments → Generate EA Token.");
      return INIT_FAILED;
   }
   EventSetTimer(5);
   Print("PyP EA v2.0 initialized. Token: ", StringSubstr(EAToken, 0, 8), "...");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   EventKillTimer();
}

void OnTimer() {
   if (!EnableTrading) return;
   FetchAndExecuteSignal();
}

//+------------------------------------------------------------------+
void FetchAndExecuteSignal() {
   string url = ApiUrl + "/api/mt4/signals?token=" + EAToken
              + "&since=" + IntegerToString((int)lastSignalTime);
   string headers = "Content-Type: application/json\r\n";
   char post[], result[];
   string resultHeaders;

   int res = WebRequest("GET", url, headers, 5000, post, result, resultHeaders);

   if (res == -1) {
      int err = GetLastError();
      if (err == 4060)
         Print("PyP EA: Add ", ApiUrl, " to allowed URLs → Tools > Options > Expert Advisors > Allow WebRequests");
      else
         Print("PyP EA: WebRequest error ", err);
      return;
   }

   if (res != 200) {
      Print("PyP EA: API returned HTTP ", res);
      return;
   }

   string body = CharArrayToString(result);
   if (body == "" || body == "null" || StringFind(body, "signal") < 0) return;

   //--- Parse all fields
   string signal     = ParseJsonString(body, "signal");
   string pair       = ParseJsonString(body, "pair");
   double confidence = ParseJsonDouble(body, "confidence");
   double sl_price   = ParseJsonDouble(body, "sl");
   double tp_price   = ParseJsonDouble(body, "tp");
   double lot_size   = ParseJsonDouble(body, "lot_size");
   int    ts         = (int)ParseJsonDouble(body, "timestamp");

   //--- Deduplicate
   if (signal == "" || ts <= (int)lastSignalTime) return;
   lastSignalTime = (datetime)ts;

   //--- Normalize pair
   StringReplace(pair, "/", "");
   StringReplace(pair, "_", "");
   if (pair == "") pair = Symbol();

   //--- Confidence gate
   if (MinConfidence > 0.0 && confidence < MinConfidence) {
      Print("PyP EA: Signal skipped — confidence ", DoubleToString(confidence, 2),
            " below threshold ", DoubleToString(MinConfidence, 2));
      return;
   }

   Print("PyP EA: Signal=", signal,
         " Pair=", pair,
         " Conf=", DoubleToString(confidence, 2),
         " SL=", DoubleToString(sl_price, 5),
         " TP=", DoubleToString(tp_price, 5),
         " Lots=", DoubleToString(lot_size, 2));

   if (signal == "BUY")  ExecuteTrade(pair, OP_BUY,  sl_price, tp_price, lot_size);
   if (signal == "SELL") ExecuteTrade(pair, OP_SELL, sl_price, tp_price, lot_size);
}

//+------------------------------------------------------------------+
void ExecuteTrade(string pair, int orderType,
                  double server_sl, double server_tp, double server_lots) {

   if (CloseOnReverse) CloseOpposite(pair, orderType);

   double price = (orderType == OP_BUY)
                  ? MarketInfo(pair, MODE_ASK)
                  : MarketInfo(pair, MODE_BID);

   if (price <= 0) {
      Print("PyP EA: Invalid price for ", pair);
      return;
   }

   double point    = MarketInfo(pair, MODE_POINT);
   int    digits   = (int)MarketInfo(pair, MODE_DIGITS);
   double pipValue = (digits == 3 || digits == 5) ? point * 10 : point;

   //--- Resolve lot size
   double lots = (ManualLotSize > 0) ? ManualLotSize
               : (server_lots > 0)   ? server_lots
               : 0.01;

   //--- Resolve SL
   double sl = 0;
   if (ManualSL_Pips > 0) {
      sl = (orderType == OP_BUY)
           ? price - ManualSL_Pips * pipValue
           : price + ManualSL_Pips * pipValue;
   } else if (server_sl > 0) {
      sl = server_sl;
   }

   //--- Resolve TP
   double tp = 0;
   if (ManualTP_Pips > 0) {
      tp = (orderType == OP_BUY)
           ? price + ManualTP_Pips * pipValue
           : price - ManualTP_Pips * pipValue;
   } else if (server_tp > 0) {
      tp = server_tp;
   }

   //--- Normalize to broker precision
   if (sl > 0) sl = NormalizeDouble(sl, digits);
   if (tp > 0) tp = NormalizeDouble(tp, digits);

   int ticket = OrderSend(pair, orderType, lots, price, Slippage,
                          sl, tp, "PyP Signal", MagicNumber, 0,
                          orderType == OP_BUY ? clrGreen : clrRed);

   if (ticket < 0)
      Print("PyP EA: OrderSend failed, error=", GetLastError());
   else
      Print("PyP EA: Order opened ticket=", ticket,
            " type=", (orderType == OP_BUY ? "BUY" : "SELL"),
            " price=", DoubleToString(price, digits),
            " SL=", DoubleToString(sl, digits),
            " TP=", DoubleToString(tp, digits),
            " lots=", DoubleToString(lots, 2));
}

//+------------------------------------------------------------------+
void CloseOpposite(string pair, int newType) {
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderSymbol() != pair || OrderMagicNumber() != MagicNumber) continue;
      if ((newType == OP_BUY  && OrderType() == OP_SELL) ||
          (newType == OP_SELL && OrderType() == OP_BUY)) {
         double closePrice = (OrderType() == OP_BUY)
                             ? MarketInfo(pair, MODE_BID)
                             : MarketInfo(pair, MODE_ASK);
         bool closed = OrderClose(OrderTicket(), OrderLots(), closePrice, Slippage, clrWhite);
         if (!closed)
            Print("PyP EA: Failed to close opposite order, error=", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
string ParseJsonString(string json, string key) {
   string search = "\"" + key + "\":\"";
   int start = StringFind(json, search);
   if (start < 0) return "";
   start += StringLen(search);
   int end = StringFind(json, "\"", start);
   if (end < 0) return "";
   return StringSubstr(json, start, end - start);
}

double ParseJsonDouble(string json, string key) {
   string search = "\"" + key + "\":";
   int start = StringFind(json, search);
   if (start < 0) return 0;
   start += StringLen(search);
   if (StringGetCharacter(json, start) == '"') start++;
   int end = start;
   while (end < StringLen(json)) {
      ushort c = StringGetCharacter(json, end);
      if (c == ',' || c == '}' || c == '"' || c == ']') break;
      end++;
   }
   return StringToDouble(StringSubstr(json, start, end - start));
}
//+------------------------------------------------------------------+

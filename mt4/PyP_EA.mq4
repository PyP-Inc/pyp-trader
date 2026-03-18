//+------------------------------------------------------------------+
//|                                                       PyP EA.mq4 |
//|                                          PyP Trading Platform    |
//|                                    https://pyp.stanlink.online   |
//+------------------------------------------------------------------+
#property copyright "PyP Trading Platform"
#property link      "https://pyp.stanlink.online"
#property version   "1.00"
#property strict

input string EAToken      = "";          // EA Token (from PyP dashboard)
input string ApiUrl       = "https://api.pyp.stanlink.online"; // API URL
input double LotSize      = 0.1;         // Lot Size
input int    MagicNumber  = 20260101;    // Magic Number
input int    Slippage     = 3;           // Slippage (points)
input bool   EnableTrading = true;       // Enable Auto Trading

// Internal state
datetime lastSignalTime = 0;
int      pollInterval   = 5; // seconds

//+------------------------------------------------------------------+
int OnInit() {
   if (EAToken == "") {
      Alert("PyP EA: EAToken is required. Get it from your PyP dashboard.");
      return INIT_FAILED;
   }
   EventSetTimer(pollInterval);
   Print("PyP EA initialized. Token: ", StringSubstr(EAToken, 0, 8), "...");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
}

//+------------------------------------------------------------------+
void OnTimer() {
   if (!EnableTrading) return;
   FetchAndExecuteSignal();
}

//+------------------------------------------------------------------+
void FetchAndExecuteSignal() {
   string url     = ApiUrl + "/api/mt4/signals?token=" + EAToken + "&since=" + IntegerToString((int)lastSignalTime);
   string headers = "Content-Type: application/json\r\n";
   char   post[];
   char   result[];
   string resultHeaders;

   int res = WebRequest("GET", url, headers, 5000, post, result, resultHeaders);

   if (res == -1) {
      int err = GetLastError();
      if (err == 4060) Print("PyP EA: Add ", ApiUrl, " to MT4 allowed URLs (Tools > Options > Expert Advisors)");
      else Print("PyP EA: WebRequest error ", err);
      return;
   }

   if (res != 200) {
      Print("PyP EA: API returned HTTP ", res);
      return;
   }

   string body = CharArrayToString(result);
   if (body == "" || body == "null" || StringFind(body, "signal") < 0) return;

   // Parse signal field
   string signal = ParseJsonString(body, "signal");
   string pair   = ParseJsonString(body, "pair");
   double conf   = ParseJsonDouble(body, "confidence");
   int    ts     = (int)ParseJsonDouble(body, "timestamp");

   if (signal == "" || ts <= (int)lastSignalTime) return;
   lastSignalTime = (datetime)ts;

   // Normalize pair: "EURUSD" or "EUR/USD" → "EURUSD"
   StringReplace(pair, "/", "");
   StringReplace(pair, "_", "");

   if (pair == "") pair = Symbol();

   Print("PyP EA: Signal=", signal, " Pair=", pair, " Conf=", DoubleToString(conf, 2));

   if (signal == "BUY")  ExecuteTrade(pair, OP_BUY);
   if (signal == "SELL") ExecuteTrade(pair, OP_SELL);
}

//+------------------------------------------------------------------+
void ExecuteTrade(string pair, int orderType) {
   // Close any opposite open trade for this pair first
   CloseOpposite(pair, orderType);

   double price = (orderType == OP_BUY) ? MarketInfo(pair, MODE_ASK) : MarketInfo(pair, MODE_BID);
   if (price <= 0) {
      Print("PyP EA: Invalid price for ", pair);
      return;
   }

   int ticket = OrderSend(pair, orderType, LotSize, price, Slippage, 0, 0,
                          "PyP Signal", MagicNumber, 0,
                          orderType == OP_BUY ? clrGreen : clrRed);

   if (ticket < 0) Print("PyP EA: OrderSend failed, error=", GetLastError());
   else Print("PyP EA: Order opened ticket=", ticket, " type=", (orderType == OP_BUY ? "BUY" : "SELL"), " price=", price);
}

//+------------------------------------------------------------------+
void CloseOpposite(string pair, int newType) {
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderSymbol() != pair || OrderMagicNumber() != MagicNumber) continue;
      if ((newType == OP_BUY && OrderType() == OP_SELL) ||
          (newType == OP_SELL && OrderType() == OP_BUY)) {
         double closePrice = (OrderType() == OP_BUY) ? MarketInfo(pair, MODE_BID) : MarketInfo(pair, MODE_ASK);
         bool closed = OrderClose(OrderTicket(), OrderLots(), closePrice, Slippage, clrWhite);
         if (!closed) Print("PyP EA: Failed to close opposite order, error=", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
// Minimal JSON string parser — extracts value for a given key
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
   // skip quote if present
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

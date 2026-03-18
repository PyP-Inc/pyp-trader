//+------------------------------------------------------------------+
//|                                                       PyP EA.mq5 |
//|                                          PyP Trading Platform    |
//|                                    https://pyp.stanlink.online   |
//+------------------------------------------------------------------+
#property copyright "PyP Trading Platform"
#property link      "https://pyp.stanlink.online"
#property version   "1.00"

input string EAToken       = "";         // EA Token (from PyP dashboard)
input string ApiUrl        = "https://api.pyp.stanlink.online"; // API URL
input double LotSize       = 0.1;        // Lot Size
input ulong  MagicNumber   = 20260101;   // Magic Number
input int    Slippage      = 3;          // Slippage (points)
input bool   EnableTrading = true;       // Enable Auto Trading

datetime lastSignalTime = 0;

//+------------------------------------------------------------------+
int OnInit() {
   if (EAToken == "") {
      Alert("PyP EA: EAToken is required. Get it from your PyP dashboard.");
      return INIT_FAILED;
   }
   EventSetTimer(5);
   Print("PyP EA initialized. Token: ", StringSubstr(EAToken, 0, 8), "...");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTimer() {
   if (EnableTrading) FetchAndExecuteSignal();
}

//+------------------------------------------------------------------+
void FetchAndExecuteSignal() {
   string url     = ApiUrl + "/api/mt4/signals?token=" + EAToken + "&since=" + IntegerToString((long)lastSignalTime);
   string headers = "Content-Type: application/json\r\n";
   char   post[], result[];
   string resultHeaders;

   int res = WebRequest("GET", url, headers, 5000, post, result, resultHeaders);
   if (res == -1) {
      if (GetLastError() == 4060)
         Print("PyP EA: Add ", ApiUrl, " to allowed URLs in Tools > Options > Expert Advisors");
      return;
   }
   if (res != 200) return;

   string body = CharArrayToString(result);
   if (StringFind(body, "signal") < 0) return;

   string signal = ParseJsonString(body, "signal");
   string pair   = ParseJsonString(body, "pair");
   long   ts     = (long)ParseJsonDouble(body, "timestamp");

   if (signal == "" || ts <= (long)lastSignalTime) return;
   lastSignalTime = (datetime)ts;

   StringReplace(pair, "/", "");
   StringReplace(pair, "_", "");
   if (pair == "") pair = Symbol();

   Print("PyP EA: Signal=", signal, " Pair=", pair);

   if (signal == "BUY")  ExecuteTrade(pair, ORDER_TYPE_BUY);
   if (signal == "SELL") ExecuteTrade(pair, ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
void ExecuteTrade(string pair, ENUM_ORDER_TYPE orderType) {
   CloseOpposite(pair, orderType);

   double price = (orderType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(pair, SYMBOL_ASK)
                  : SymbolInfoDouble(pair, SYMBOL_BID);
   if (price <= 0) return;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = pair;
   req.volume    = LotSize;
   req.type      = orderType;
   req.price     = price;
   req.deviation = Slippage;
   req.magic     = MagicNumber;
   req.comment   = "PyP Signal";
   req.type_filling = ORDER_FILLING_IOC;

   if (!OrderSend(req, res))
      Print("PyP EA: OrderSend failed, retcode=", res.retcode);
   else
      Print("PyP EA: Order opened ticket=", res.order, " price=", res.price);
}

//+------------------------------------------------------------------+
void CloseOpposite(string pair, ENUM_ORDER_TYPE newType) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != pair) continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if ((newType == ORDER_TYPE_BUY  && posType == POSITION_TYPE_SELL) ||
          (newType == ORDER_TYPE_SELL && posType == POSITION_TYPE_BUY)) {
         MqlTradeRequest req = {};
         MqlTradeResult  res = {};
         req.action = TRADE_ACTION_DEAL;
         req.position = ticket;
         req.symbol = pair;
         req.volume = PositionGetDouble(POSITION_VOLUME);
         req.type   = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         req.price  = (req.type == ORDER_TYPE_SELL)
                      ? SymbolInfoDouble(pair, SYMBOL_BID)
                      : SymbolInfoDouble(pair, SYMBOL_ASK);
         req.deviation = Slippage;
         req.magic  = MagicNumber;
         req.type_filling = ORDER_FILLING_IOC;
         OrderSend(req, res);
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

#property description   "An endpoint for remote control of MetaTrader 4 via ZeroMQ sockets."
#property copyright     "Copyright 2020, CoeJoder"
#property link          "https://github.com/CoeJoder/metatrader4-server"
#property version       "1.0"
#property strict
#property show_inputs

#include <stdlib.mqh>
// see: https://github.com/dingmaotu/mql-zmq
#include <Zmq/Zmq.mqh>
// see: https://www.mql5.com/en/code/13663
#include <json/JAson.mqh>

// input parameters
extern string SCRIPT_NAME = "ZeroMQ_Server";
extern string ADDRESS = "tcp://*:28282";
extern int REQUEST_POLLING_INTERVAL = 500;
extern int RESPONSE_TIMEOUT = 5000;
extern int MIN_POINT_DISTANCE = 3;
extern bool VERBOSE = true;

// response message keys
const string KEY_RESPONSE = "response";
const string KEY_ERROR_CODE = "error_code";
const string KEY_ERROR_CODE_DESCRIPTION = "error_code_description";
const string KEY_ERROR_MESSAGE = "error_message";
const string KEY_WARNING = "warning";

// types of requests
enum RequestAction {
    GET_ACCOUNT_INFO,
    GET_ACCOUNT_INFO_INTEGER,
    GET_ACCOUNT_INFO_DOUBLE,
    GET_SYMBOL_INFO,
    GET_SYMBOL_MARKET_INFO,
    GET_SYMBOL_INFO_INTEGER,
    GET_SYMBOL_INFO_DOUBLE,
    GET_SYMBOL_INFO_STRING,
    GET_SYMBOL_TICK,
    GET_ORDER,
    GET_ORDERS,
    GET_HISTORICAL_ORDERS,
    GET_SYMBOLS,
    GET_OHLCV,
    GET_SIGNALS,
    GET_SIGNAL_INFO,
    DO_ORDER_SEND,
    DO_ORDER_CLOSE,
    DO_ORDER_DELETE,
    DO_ORDER_MODIFY,
    RUN_INDICATOR
};

// types of indicators
enum Indicator {
    iAC,
    iAD,
    iADX,
    iAlligator,
    iAO,
    iATR,
    iBearsPower,
    iBands,
    iBandsOnArray,
    iBullsPower,
    iCCI,
    iCCIOnArray,
    iCustom,
    iDeMarker,
    iEnvelopes,
    iEnvelopesOnArray,
    iForce,
    iFractals,
    iGator,
    iIchimoku,
    iBWMFI,
    iMomentum,
    iMomentumOnArray,
    iMFI,
    iMA,
    iMAOnArray,
    iOsMA,
    iMACD,
    iOBV,
    iSAR,
    iRSI,
    iRSIOnArray,
    iRVI,
    iStdDev,
    iStdDevOnArray,
    iStochastic,
    iWPR
};

// ZeroMQ sockets
Context* context = NULL;
Socket* socket = NULL;

int OnInit() {
    ENUM_INIT_RETCODE retcode = INIT_SUCCEEDED;

    // workaround for OnInit() being called twice when script is attached via .ini at terminal startup
    if (context == NULL) {
        // ZeroMQ context and sockets
        context = new Context(SCRIPT_NAME);
        context.setBlocky(false);
        socket = new Socket(context, ZMQ_REP);
        socket.setSendHighWaterMark(1);
        socket.setReceiveHighWaterMark(1);
        socket.setSendTimeout(RESPONSE_TIMEOUT);
        if (!socket.bind(ADDRESS)) {
            Alert(StringFormat("Failed to bind socket on %s: %s", ADDRESS, Zmq::errorMessage(Zmq::errorNumber())));
            retcode = INIT_FAILED;
        }
        else {
            Print(StringFormat("Listening for requests on %s", ADDRESS));
        }
    }
    return retcode;
}

void OnDeinit(const int reason) {
    if (context != NULL) {
        Print("Unbinding listening socket...");
        socket.unbind(ADDRESS);

        // destroy ZeroMQ context
        context.destroy(0);

        // deallocate ZeroMQ objects
        delete socket;
        delete context;
        socket = NULL;
        context = NULL;
    }
}

void OnStart() {
    PollItem poller[1];
    socket.fillPollItem(poller[0], ZMQ_POLLIN);
    ZmqMsg inMessage;
    while (IsRunning()) {
        if (-1 == Socket::poll(poller, REQUEST_POLLING_INTERVAL)) {
            Print("Failed input polling: " + Zmq::errorMessage(Zmq::errorNumber()));
        }
        else if (poller[0].hasInput()) {
            if (_socketReceive(inMessage, true)) {
                if (inMessage.size() > 0) {
                    string dataStr = inMessage.getData();
                    Trace("Received request: " + dataStr);
                    // responsible for sending response
                    _processRequest(dataStr);
                }
                else {
                    sendError("Request was empty.");
                }
            }
        }
    }
}

bool _socketReceive(ZmqMsg& msg, bool nowait=false) {
    bool success = true;
    if (!socket.recv(msg, nowait)) {
        Print("Failed to receive request.");
        success = false;
    }
    return success;
}

bool _socketSend(string response=NULL, bool nowait=false) {
    bool success = true;
    if ((response == NULL && !socket.send(nowait)) || (response != NULL && !socket.send(response, nowait))) {
        Alert("Critical error!  Failed to send response to client: " + Zmq::errorMessage(Zmq::errorNumber()));
        success = false;
    }
    return success;
}

void _processRequest(string dataStr) {
    // parse JSON request
    CJAVal req;
    if (!req.Deserialize(dataStr, CP_UTF8)) {
        sendError("Failed to parse request.");
        return;
    }
    string actionStr = req["action"].ToStr();
    if (actionStr == "") {
        sendError("No request action specified.");
        return;
    }

    // perform the action
    RequestAction action = (RequestAction)-1;
    switch(StringToEnum(actionStr, action)) {
        case GET_ACCOUNT_INFO:
            Get_AccountInfo();
            break;
        case GET_ACCOUNT_INFO_INTEGER:
            Get_AccountInfoInteger(req);
            break;
        case GET_ACCOUNT_INFO_DOUBLE:
            Get_AccountInfoDouble(req);
            break;
        case GET_SYMBOL_INFO:
            Get_SymbolInfo(req);
            break;
        case GET_SYMBOL_MARKET_INFO:
            Get_SymbolMarketInfo(req);
            break;
        case GET_SYMBOL_INFO_INTEGER:
            Get_SymbolInfoInteger(req);
            break;
        case GET_SYMBOL_INFO_DOUBLE:
            Get_SymbolInfoDouble(req);
            break;
        case GET_SYMBOL_INFO_STRING:
            Get_SymbolInfoString(req);
            break;
        case GET_SYMBOL_TICK:
            Get_SymbolTick(req);
            break;
        case GET_ORDER:
            Get_Order(req);
            break;
        case GET_ORDERS:
            Get_Orders();
            break;
        case GET_HISTORICAL_ORDERS:
            Get_HistoricalOrders();
            break;
        case GET_SYMBOLS:
            Get_Symbols();
            break;
        case GET_OHLCV:
            Get_OHLCV(req);
            break;
        case GET_SIGNALS:
            Get_Signals();
            break;
        case GET_SIGNAL_INFO:
            Get_SignalInfo(req);
            break;
        case DO_ORDER_SEND:
            Do_OrderSend(req);
            break;
        case DO_ORDER_MODIFY:
            Do_OrderModify(req);
            break;
        case DO_ORDER_CLOSE:
            Do_OrderClose(req);
            break;
        case DO_ORDER_DELETE:
            Do_OrderDelete(req);
            break;
        case RUN_INDICATOR:
            Run_Indicator(req);
            break;
        default: {
            string errorStr = StringFormat("Unrecognized requested action (%s).", actionStr);
            Print(errorStr);
            sendError(errorStr);
            break;
        }
    }
}

void _serializeAndSendResponse(CJAVal& resp) {
    string strResp = resp.Serialize();
    if (_socketSend(strResp)) {
        Trace("Sent response: " + strResp);
    }
}

void sendResponse(CJAVal& data, string warning=NULL) {
    CJAVal resp;
    resp[KEY_RESPONSE].Set(data);
    if (warning != NULL) {
        resp[KEY_WARNING] = warning;
    }
    _serializeAndSendResponse(resp);
}

void sendResponse(string val, string warning=NULL) {
    CJAVal resp;
    resp[KEY_RESPONSE] = val;
    if (warning != NULL) {
        resp[KEY_WARNING] = warning;
    }
    _serializeAndSendResponse(resp);
}

void sendResponse(double val, string warning=NULL) {
    CJAVal resp;
    resp[KEY_RESPONSE] = val;
    if (warning != NULL) {
        resp[KEY_WARNING] = warning;
    }
    _serializeAndSendResponse(resp);
}

void sendResponse(long val, string warning=NULL) {
    CJAVal resp;
    resp[KEY_RESPONSE] = val;
    if (warning != NULL) {
        resp[KEY_WARNING] = warning;
    }
    _serializeAndSendResponse(resp);
}

void sendError(int code, string msg) {
    CJAVal resp;
    resp[KEY_ERROR_CODE] = code;
    resp[KEY_ERROR_CODE_DESCRIPTION] = ErrorDescription(code);
    resp[KEY_ERROR_MESSAGE] = msg;
    _serializeAndSendResponse(resp);
}

void sendError(int code) {
    CJAVal resp;
    resp[KEY_ERROR_CODE] = code;
    resp[KEY_ERROR_CODE_DESCRIPTION] = ErrorDescription(code);
    _serializeAndSendResponse(resp);
}

void sendError(string msg) {
    CJAVal resp;
    resp[KEY_ERROR_MESSAGE] = msg;
    _serializeAndSendResponse(resp);
}

void sendErrorMissingParam(string paramName) {
    sendError(StringFormat("Missing \"%s\" param.", paramName));
}

bool assertParamExists(CJAVal& req, string paramName) {
    if (IsNullOrMissing(req, paramName)) {
        sendErrorMissingParam(paramName);
        return false;
    }
    return true;
}

bool assertParamArrayExistsAndNotEmpty(CJAVal& req, string paramName) {
    if (!assertParamExists(req, paramName)) {
        return false;
    }
    CJAVal* param = req[paramName];
    if (param.m_type != jtARRAY) {
        sendError(StringFormat("Param \"%s\" is not an array.", paramName));
        return false;
    }
    if (param.Size() == 0) {
        sendError(StringFormat("Param \"%s[]\" is empty.", paramName));
        return false;
    }
    return true;
}

// selects an order and sends it to the client, or sends an error code if not found
void sendOrder(int ticket, string warning=NULL) {
    if (OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) {
        // order is pending or open
        CJAVal newOrder;
        _getSelectedOrder(newOrder);
        sendResponse(newOrder, warning);
        return;
    }
    else {
        // order was not found in Trades tab; check Account History tab
        if (OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY)) {
            // order is closed
            CJAVal newOrder;
            _getSelectedOrder(newOrder);
            sendResponse(newOrder, warning);
            return;
        }
        else {
            // order was not found; this should never happen for a valid ticket # unless there is a server error
            sendError(StringFormat("Order # %d is not found in the Trades or Account History tabs.", ticket));
            return;
        }
    }
}

void Get_AccountInfo() {
    long login = AccountInfoInteger(ACCOUNT_LOGIN);
    long tradeMode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
    string name = AccountInfoString(ACCOUNT_NAME);
    string server = AccountInfoString(ACCOUNT_SERVER);
    string currency = AccountInfoString(ACCOUNT_CURRENCY);
    string company = AccountInfoString(ACCOUNT_COMPANY);

    CJAVal account_info;
    account_info["login"] = login;
    account_info["trade_mode"] = tradeMode;
    account_info["name"] = name;
    account_info["server"] = server;
    account_info["currency"] = currency;
    account_info["company"] = company;
    sendResponse(account_info);
}

void Get_AccountInfoInteger(CJAVal& req) {
    // use either property's name or id, giving priority to name
    if (!IsNullOrMissing(req, "property_name")) {
        string propertyName = req["property_name"].ToStr();
        ENUM_ACCOUNT_INFO_INTEGER action = (ENUM_ACCOUNT_INFO_INTEGER)-1;
        action = StringToEnum(propertyName, action);
        if (action == -1) {
            sendError(StringFormat("Unrecognized account integer property: %s", propertyName));
            return;
        }
        else {
            sendResponse(AccountInfoInteger(action));
            return;
        }
    }
    else if (!IsNullOrMissing(req, "property_id")) {
        int propertyId = (int)req["property_id"].ToInt();
        sendResponse(AccountInfoInteger(propertyId));
        return;
    }
    else {
        sendError("Must include either \"property_name\" or \"property_id\" param.");
        return;
    }
}

void Get_AccountInfoDouble(CJAVal& req) {
    // use either property's name or id, giving priority to name
    if (!IsNullOrMissing(req, "property_name")) {
        string propertyName = req["property_name"].ToStr();
        ENUM_ACCOUNT_INFO_DOUBLE action = (ENUM_ACCOUNT_INFO_DOUBLE)-1;
        action = StringToEnum(propertyName, action);
        if (action == -1) {
            sendError(StringFormat("Unrecognized account double property: %s", propertyName));
            return;
        }
        else {
            sendResponse(AccountInfoDouble(action));
            return;
        }
    }
    else if (!IsNullOrMissing(req, "property_id")) {
        int propertyId = (int)req["property_id"].ToInt();
        sendResponse(AccountInfoDouble(propertyId));
        return;
    }
    else {
        sendError("Must include either \"property_name\" or \"property_id\" param.");
        return;
    }
}

void Get_SymbolInfo(CJAVal& req) {
    if (!assertParamArrayExistsAndNotEmpty(req, "names")) {
        return;
    }
    CJAVal* names = req["names"];
    CJAVal symbols;
    for (int i = 0; i < names.Size(); i++) {
        string name = names[i].ToStr();
        if (!SymbolSelect(name, true)) {
            sendError(GetLastError(), name);
            return;
        }
        double point = SymbolInfoDouble(name, SYMBOL_POINT);                                // Point size in the quote currency
        long digits = SymbolInfoInteger(name, SYMBOL_DIGITS);                               // Digits after decimal point
        double volume_min = SymbolInfoDouble(name, SYMBOL_VOLUME_MIN);                      // Minimal volume for a deal
        double volume_step = SymbolInfoDouble(name, SYMBOL_VOLUME_STEP);                    // Minimal volume change step for deal execution
        double volume_max = SymbolInfoDouble(name, SYMBOL_VOLUME_MAX);                      // Maximal volume for a deal
        double trade_contract_size = SymbolInfoDouble(name, SYMBOL_TRADE_CONTRACT_SIZE);    // Trade contract size in the base currency
        double trade_tick_value = SymbolInfoDouble(name, SYMBOL_TRADE_TICK_VALUE);          // Tick value in the deposit currency
        double trade_tick_size = SymbolInfoDouble(name, SYMBOL_TRADE_TICK_SIZE);            // Tick size in points
        long trade_stops_level = SymbolInfoInteger(name, SYMBOL_TRADE_STOPS_LEVEL);         // Stop level in points
        long trade_freeze_level = SymbolInfoInteger(name, SYMBOL_TRADE_FREEZE_LEVEL);       // Order freeze level in points

        CJAVal symbol;
        symbol["name"] = name;
        symbol["point"] = point;
        symbol["digits"] = digits;
        symbol["volume_min"] = volume_min;
        symbol["volume_step"] = volume_step;
        symbol["volume_max"] = volume_max;
        symbol["trade_contract_size"] = trade_contract_size;
        symbol["trade_tick_value"] = trade_tick_value;
        symbol["trade_tick_size"] = trade_tick_size;
        symbol["trade_stops_level"] = trade_stops_level;
        symbol["trade_freeze_level"] = trade_freeze_level;
        symbols[name].Set(symbol);
    }
    sendResponse(symbols);
    return;
}

void Get_SymbolMarketInfo(CJAVal& req) {
    if (!assertParamExists(req, "symbol") || !assertParamExists(req, "property")) {
        return;
    }
    string symbol = req["symbol"].ToStr();
    string strProperty = req["property"].ToStr();

    if (!SymbolSelect(symbol, true)) {
        sendError(GetLastError(), symbol);
        return;
    }

    ENUM_MARKETINFO prop = (ENUM_MARKETINFO)-1;
    prop = StringToEnum(strProperty, prop);
    if (prop != -1) {
        sendResponse(MarketInfo(symbol, prop));
        return;
    }
    else {
        sendError(StringFormat("Unrecognized market info property: %s", strProperty));
        return;
    }
}

void Get_SymbolInfoInteger(CJAVal& req) {
    if (!assertParamExists(req, "symbol")) {
        return;
    }
    string symbol = req["symbol"].ToStr();

    // use either property's name or id, giving priority to name
    if (!IsNullOrMissing(req, "property_name")) {
        string propertyName = req["property_name"].ToStr();
        ENUM_SYMBOL_INFO_INTEGER action = (ENUM_SYMBOL_INFO_INTEGER)-1;
        action = StringToEnum(propertyName, action);
        if (action == -1) {
            sendError(StringFormat("Unrecognized symbol integer property: %s", propertyName));
            return;
        }
        else {
            long propertyValue;
            if (!SymbolInfoInteger(symbol, action, propertyValue)) {
                sendError(GetLastError());
                return;
            }
            else {
                sendResponse(propertyValue);
                return;
            }
        }
    }
    else if (!IsNullOrMissing(req, "property_id")) {
        int propertyId = (int)req["property_id"].ToInt();
        long propertyValue;
        if (!SymbolInfoInteger(symbol, propertyId, propertyValue)) {
            sendError(GetLastError());
            return;
        }
        else {
            sendResponse(propertyValue);
            return;
        }
    }
    else {
        sendError("Must include either \"property_name\" or \"property_id\" param.");
        return;
    }
}

void Get_SymbolInfoDouble(CJAVal& req) {
    if (!assertParamExists(req, "symbol")) {
        return;
    }
    string symbol = req["symbol"].ToStr();

    // use either property's name or id, giving priority to name
    if (!IsNullOrMissing(req, "property_name")) {
        string propertyName = req["property_name"].ToStr();
        ENUM_SYMBOL_INFO_DOUBLE action = (ENUM_SYMBOL_INFO_DOUBLE)-1;
        action = StringToEnum(propertyName, action);
        if (action == -1) {
            sendError(StringFormat("Unrecognized symbol double property: %s", propertyName));
            return;
        }
        else {
            double propertyValue;
            if (!SymbolInfoDouble(symbol, action, propertyValue)) {
                sendError(GetLastError());
                return;
            }
            else {
                sendResponse(propertyValue);
                return;
            }
        }
    }
    else if (!IsNullOrMissing(req, "property_id")) {
        int propertyId = (int)req["property_id"].ToInt();
        double propertyValue;
        if (!SymbolInfoDouble(symbol, propertyId, propertyValue)) {
            sendError(GetLastError());
            return;
        }
        else {
            sendResponse(propertyValue);
            return;
        }
    }
    else {
        sendError("Must include either \"property_name\" or \"property_id\" param.");
        return;
    }
}

void Get_SymbolInfoString(CJAVal& req) {
    if (!assertParamExists(req, "symbol")) {
        return;
    }
    string symbol = req["symbol"].ToStr();

    // use either property's name or id, giving priority to name
    if (!IsNullOrMissing(req, "property_name")) {
        string propertyName = req["property_name"].ToStr();
        ENUM_SYMBOL_INFO_STRING action = (ENUM_SYMBOL_INFO_STRING)-1;
        action = StringToEnum(propertyName, action);
        if (action == -1) {
            sendError(StringFormat("Unrecognized symbol string property: %s", propertyName));
            return;
        }
        else {
            string propertyValue;
            if (!SymbolInfoString(symbol, action, propertyValue)) {
                sendError(GetLastError());
                return;
            }
            else {
                sendResponse(propertyValue);
                return;
            }
        }
    }
    else if (!IsNullOrMissing(req, "property_id")) {
        int propertyId = (int)req["property_id"].ToInt();
        string propertyValue;
        if (!SymbolInfoString(symbol, propertyId, propertyValue)) {
            sendError(GetLastError());
            return;
        }
        else {
            sendResponse(propertyValue);
            return;
        }
    }
    else {
        sendError("Must include either \"property_name\" or \"property_id\" param.");
        return;
    }
}

void Get_SymbolTick(CJAVal& req) {
    if (!assertParamExists(req, "symbol")) {
        return;
    }
    string symbol = req["symbol"].ToStr();

    if (!SymbolSelect(symbol, true)) {
        sendError(GetLastError(), symbol);
        return;
    }

    MqlTick lastTick;
    if(SymbolInfoTick(symbol, lastTick)) {
        CJAVal tick;
        tick["time"] = (long)lastTick.time;
        tick["bid"] = lastTick.bid;
        tick["ask"] = lastTick.ask;
        tick["last"] = lastTick.last;
        tick["volume"] = (long)lastTick.volume;
        sendResponse(tick);
        return;
    }
    else {
        sendError(GetLastError());
        return;
    }
}

void Get_Order(CJAVal& req) {
    if (!assertParamExists(req, "ticket")) {
        return;
    }
    int ticket = (int)req["ticket"].ToInt();
    sendOrder(ticket);
}

void Get_Orders() {
    _getOrders(MODE_TRADES);
}

void Get_HistoricalOrders() {
   _getOrders(MODE_HISTORY);
}

void _getOrders(int mode) {
    CJAVal orders;
    int total = (mode == MODE_HISTORY ? OrdersHistoryTotal() : OrdersTotal());
    // always count backwards
    for(int pos = total - 1; pos >= 0; pos--) {
        if (!OrderSelect(pos, SELECT_BY_POS, mode)) {
            int errorCode = GetLastError();
            sendError(errorCode, StringFormat("Failed to select order # %d.", pos));
            return;
        }
        else {
            // order selected
            CJAVal curOrder;
            _getSelectedOrder(curOrder);
            orders.Add(curOrder);
        }
    }
    sendResponse(orders);
}

void _getSelectedOrder(CJAVal& order) {
    order["ticket"] = OrderTicket();
    order["magic_number"] = OrderMagicNumber();
    order["symbol"] = OrderSymbol();
    order["order_type"] = OrderType();
    order["lots"] = OrderLots();
    order["open_price"] = OrderOpenPrice();
    order["close_price"] = OrderClosePrice();
    order["open_time"] = TimeToStr(OrderOpenTime(), TIME_DATE|TIME_SECONDS);
    order["close_time"] = TimeToStr(OrderCloseTime(), TIME_DATE|TIME_SECONDS);
    order["expiration"] = TimeToStr(OrderExpiration(), TIME_DATE|TIME_SECONDS);
    order["sl"] = OrderStopLoss();
    order["tp"] = OrderTakeProfit();
    order["profit"] = OrderProfit();
    order["commission"] = OrderCommission();
    order["swap"] = OrderSwap();
    order["comment"] = OrderComment();
}

void Get_Symbols() {
    CJAVal symbols;
    bool onlyMarketWatch = false;
    int count = SymbolsTotal(onlyMarketWatch);
    for (int i = 0; i < count; i++) {
        symbols.Add(SymbolName(i, onlyMarketWatch));
    }
    sendResponse(symbols);
}

void Get_OHLCV(CJAVal& req) {
    if (!assertParamExists(req, "symbol") || !assertParamExists(req, "timeframe")
            || !assertParamExists(req, "limit") || !assertParamExists(req, "timeout")) {
        return;
    }
    string symbol = req["symbol"].ToStr();
    int timeframe = (int)req["timeframe"].ToInt();
    int limit = (int)req["limit"].ToInt();
    long timeout = req["timeout"].ToInt();
    datetime now = TimeCurrent();

    if (!SymbolSelect(symbol, true)) {
        sendError(GetLastError(), symbol);
        return;
    }

    MqlRates rates[];
    bool reverseOrder = false;  // oldest-to-newest
    ArraySetAsSeries(rates, reverseOrder);

    // need to poll, as data may not be immediately available
    int delay = 100; // milliseconds
    long maxTries = timeout / delay;
    int numResults = -1;
    for (int try = 0; try < maxTries && numResults == -1; try++) {
        numResults = CopyRates(symbol, timeframe, now, limit, rates);
        if (numResults == -1) {
            Sleep(delay);
        }
    }
    if (numResults == -1) {
        sendError("Timed out waiting for OHLCV data.");
        return;
    }
    else {
        // success
        CJAVal ohlcv;
        for (int i = 0; i < numResults; i++) {
            CJAVal curBar;
            curBar["time"] = (long)rates[i].time;
            curBar["open"] = rates[i].open;
            curBar["high"] = rates[i].high;
            curBar["low"] = rates[i].low;
            curBar["close"] = rates[i].close;
            curBar["tick_volume"] = rates[i].tick_volume;
            ohlcv.Add(curBar);
        }
        sendResponse(ohlcv);
        return;
    }
}

void Get_Signals() {
    CJAVal signals;
    int total = SignalBaseTotal();
    for (int i = 0; i < total; i++) {
        if (!SignalBaseSelect(i)) {
            sendError(GetLastError());
            return;
        }
        else {
            signals.Add(SignalBaseGetString(SIGNAL_BASE_NAME));
        }
    }
    sendResponse(signals);
}

void Get_SignalInfo(CJAVal& req) {
    if (!assertParamArrayExistsAndNotEmpty(req, "names")) {
        return;
    }
    CJAVal* reqNames = req["names"];
    CJAVal signals;
    int total = SignalBaseTotal();
    for (int i = 0; i < total; i++) {
        if (!SignalBaseSelect(i)) {
            sendError(GetLastError());
            return;
        }
        else {
            // signal selected
            string name = SignalBaseGetString(SIGNAL_BASE_NAME);
            if (ArrayEraseElement(reqNames.m_e, name)) {
                CJAVal signal;
                signal["author_login"] = SignalBaseGetString(SIGNAL_BASE_AUTHOR_LOGIN);
                signal["broker"] = SignalBaseGetString(SIGNAL_BASE_BROKER);
                signal["broker_server"] = SignalBaseGetString(SIGNAL_BASE_BROKER_SERVER);
                signal["name"] = name;
                signal["currency"] = SignalBaseGetString(SIGNAL_BASE_CURRENCY);
                signal["date_published"] = SignalBaseGetInteger(SIGNAL_BASE_DATE_PUBLISHED);
                signal["date_started"] = SignalBaseGetInteger(SIGNAL_BASE_DATE_STARTED);
                signal["id"] = SignalBaseGetInteger(SIGNAL_BASE_ID);
                signal["leverage"] = SignalBaseGetInteger(SIGNAL_BASE_LEVERAGE);
                signal["pips"] = SignalBaseGetInteger(SIGNAL_BASE_PIPS);
                signal["rating"] = SignalBaseGetInteger(SIGNAL_BASE_RATING);
                signal["subscribers"] = SignalBaseGetInteger(SIGNAL_BASE_SUBSCRIBERS);
                signal["trades"] = SignalBaseGetInteger(SIGNAL_BASE_TRADES);
                signal["trade_mode"] = SignalBaseGetInteger(SIGNAL_BASE_TRADE_MODE);
                signal["balance"] = SignalBaseGetDouble(SIGNAL_BASE_BALANCE);
                signal["equity"] = SignalBaseGetDouble(SIGNAL_BASE_EQUITY);
                signal["gain"] = SignalBaseGetDouble(SIGNAL_BASE_GAIN);
                signal["max_drawdown"] = SignalBaseGetDouble(SIGNAL_BASE_MAX_DRAWDOWN);
                signal["price"] = SignalBaseGetDouble(SIGNAL_BASE_PRICE);
                signal["roi"] = SignalBaseGetDouble(SIGNAL_BASE_ROI);
                signals[name].Set(signal);
            }
        }
    }
    if (reqNames.Size() == 0) {
        sendResponse(signals);
        return;
    }
    else {
        sendError(StringFormat("Signals not found: %s", reqNames.Serialize()));
        return;
    }
}

void Do_OrderSend(CJAVal& req) {
    if (!assertParamExists(req, "symbol") || !assertParamExists(req, "order_type")
            || !assertParamExists(req, "lots") || !assertParamExists(req, "comment")) {
        return;
    }

    // stop-loss and take-profit params must be either relative or absolute, but not both
    if (!IsNullOrMissing(req, "sl") && !IsNullOrMissing(req, "sl_points")) {
        sendError("Stop-loss cannot be both relative (sl_points) and absolute (sl).  Specify one or the other.");
        return;
    }
    if (!IsNullOrMissing(req, "tp") && !IsNullOrMissing(req, "tp_points")) {
        sendError("Take-profit cannot be both relative (tp_points) and absolute (tp).  Specify one or the other.");
        return;
    }

    string symbol = req["symbol"].ToStr();
    int orderType = (int)req["order_type"].ToInt();
    double lots = req["lots"].ToDbl();
    string comment = req["comment"].ToStr();

    if (!SymbolSelect(symbol, true)) {
        sendError(GetLastError(), symbol);
        return;
    }

    if (!IsValidTradeOperation(orderType)) {
        sendError(StringFormat("Invalid trade operation: %d", orderType));
        return;
    }

    if (IsPendingOrder(orderType) && IsNullOrMissing(req, "price")) {
        sendError("Cannot place a pending order without the \"price\" parameter.");
        return;
    }

    // use default values as needed for the optional request params
    double price = GetDefault(req, "price", DefaultOpenPrice(symbol, orderType));
    int slippage = GetDefault(req, "slippage", DefaultSlippage(symbol));
    double stopLoss = GetDefault(req, "sl", (double)NULL);
    double takeProfit = GetDefault(req, "tp", (double)NULL);
    int stopLossPoints = GetDefault(req, "sl_points", (int)NULL);
    int takeProfitPoints = GetDefault(req, "tp_points", (int)NULL);

    // price & volume normalization
    lots = NormalizeLots(symbol, lots);
    price = NormalizePrice(symbol, price);
    slippage = NormalizePoints(symbol, slippage);

    // ECN brokers require order to be opened before sl/tp is specified
    int ticket = OrderSend(symbol, orderType, lots, price, slippage, 0, 0, comment);
    if (ticket < 0) {
        sendError(GetLastError(), "Failed to send order.");
        return;
    }
    else {
        // order created; now select it
        if (!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) {
            // order was not found in Trades tab; check Account History tab in case it already closed
            if (OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY)) {
                // order is closed; return it with a warning
                CJAVal newOrder;
                _getSelectedOrder(newOrder);
                sendResponse(newOrder, StringFormat("Order # %d was closed immediately after being opened.", ticket));
                return;
            }
            else {
                // new order was not found; this should never happen unless there is a server error
                sendError(StringFormat("Order # %d was created, but is not found in the Trades or Account History tabs.", ticket));
                return;
            }
        }
        else {
            // order is open/pending and is selected
            // add sl/tp if necessary
            if (_modifySelectedOrder(NULL, stopLoss, takeProfit, stopLossPoints, takeProfitPoints)) {
                // reselect the order and send it back to client
                sendOrder(ticket);
                return;
            }
            else {
                sendError(GetLastError(), "Order was created, but failed to set sl/tp.");
                return;
            }
        }
    }
}

void Do_OrderModify(CJAVal& req) {
    if (!assertParamExists(req, "ticket")) {
        return;
    }
    int ticket = (int)req["ticket"].ToInt();

    // stop-loss and take-profit params must be either relative or absolute, but not both
    if (!IsNullOrMissing(req, "sl") && !IsNullOrMissing(req, "sl_points")) {
        sendError("Stop-loss cannot be both relative (sl_points) and absolute (sl).  Specify one or the other.");
        return;
    }
    if (!IsNullOrMissing(req, "tp") && !IsNullOrMissing(req, "tp_points")) {
        sendError("Take-profit cannot be both relative (tp_points) and absolute (tp).  Specify one or the other.");
        return;
    }

    if (!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) {
        sendError(StringFormat("Order # %d not found.", ticket));
        return;
    }
    else {
        // order selected
        // overwrite existing values with request params if provided
        double newPrice = GetDefault(req, "price", (double)NULL);
        double stopLoss = GetDefault(req, "sl", (double)NULL);
        double takeProfit = GetDefault(req, "tp", (double)NULL);
        int newStopLossPoints = GetDefault(req, "sl_points", (int)NULL);
        int newTakeProfitPoints = GetDefault(req, "tp_points", (int)NULL);

        if (_modifySelectedOrder(newPrice, stopLoss, takeProfit, newStopLossPoints, newTakeProfitPoints)) {
            // reselect the order and send it back to client
            sendOrder(ticket);
            return;
        }
        else {
            sendError(GetLastError(), StringFormat("Failed to modify order # %d.", ticket));
            return;
        }
    }
}

// modifies a selected order, nudging the given values to obey the trading rules
// see: https://book.mql4.com/appendix/limits
bool _modifySelectedOrder(double price=NULL, double stopLoss=NULL, double takeProfit=NULL, int stopLossPoints=NULL, int takeProfitPoints=NULL) {
    if (price == NULL && stopLoss == NULL && takeProfit == NULL && stopLossPoints == NULL && takeProfitPoints == NULL) {
        return true;
    }
    int ticket = OrderTicket();
    string symbol = OrderSymbol();
    int type = OrderType();

    int stopLevelPoints = (int)MarketInfo(symbol, MODE_STOPLEVEL);
    // +1 to deal with non-inclusive inequality
    int freezeLevelPoints = (int)MarketInfo(symbol, MODE_FREEZELEVEL) + 1;
    int minDistPoints = (int)MathMax(stopLevelPoints, (int)MathMax(freezeLevelPoints, MIN_POINT_DISTANCE));
    // round up just to be safe
    double minDist = NormalizePriceUp(symbol, PointsToDouble(symbol, minDistPoints));
    double ask = MarketInfo(symbol, MODE_ASK);
    double bid = MarketInfo(symbol, MODE_BID);

    if (IsPendingOrder(type) && price != NULL) {
        price = NormalizePrice(symbol, _getPriceMod(type, ask, bid, minDist, price));
    }
    else {
        if (stopLoss == NULL && takeProfit == NULL && stopLossPoints == NULL && takeProfitPoints == NULL) {
            // nothing left to do
            return true;
        }
        price = OrderOpenPrice();
    }

    if (stopLossPoints != NULL) {
        // relative value given
        double dist = PointsToDouble(symbol, MathMax(stopLossPoints, minDistPoints));
        stopLoss = NormalizePrice(symbol, _getSLMod(type, ask, bid, dist, price));
    }
    else if (stopLoss != NULL) {
        // absolute value given
        stopLoss = NormalizePrice(symbol, _getSLMod(type, ask, bid, minDist, price, stopLoss));
    }
    else {
        stopLoss = OrderStopLoss();
    }

    if (takeProfitPoints != NULL) {
        // relative value given
        double dist = PointsToDouble(symbol, MathMax(takeProfitPoints, minDistPoints));
        takeProfit = NormalizePrice(symbol, _getTPMod(type, ask, bid, dist, price));
    }
    else if (takeProfit != NULL) {
        // absolute value given
        takeProfit = NormalizePrice(symbol, _getTPMod(type, ask, bid, minDist, price, takeProfit));
    }
    else {
        takeProfit = OrderTakeProfit();
    }

    return OrderModify(ticket, price, stopLoss, takeProfit, 0, CLR_NONE);
}

// given a price, gets the mod price
// see: https://book.mql4.com/appendix/limits
double _getPriceMod(int orderType, double ask, double bid, double minDist, double price) {
    if (orderType != OP_BUY && orderType != OP_SELL) {
        if (orderType == OP_BUYLIMIT) {
            price = MathMin(ask - minDist, price);
        }
        else if (orderType == OP_SELLLIMIT) {
            price = MathMax(bid + minDist, price);
        }
        else if (orderType == OP_BUYSTOP) {
            price = MathMax(ask + minDist, price);
        }
        else if (orderType == OP_SELLSTOP) {
            price = MathMin(bid - minDist, price);
        }
    }
    return price;
}

// given an absolute stop-loss, gets the mod stop-loss
// see: https://book.mql4.com/appendix/limits
double _getSLMod(int orderType, double ask, double bid, double minDist, double price, double stopLoss) {
    if (orderType == OP_BUY) {
        if (bid - stopLoss < minDist) {
            stopLoss = bid - minDist;
        }
    }
    else if (orderType == OP_SELL) {
        if (stopLoss - ask < minDist) {
            stopLoss = ask + minDist;
        }
    }
    else if (orderType == OP_BUYLIMIT) {
        if (price - stopLoss < minDist) {
            stopLoss = price - minDist;
        }
    }
    else if (orderType == OP_SELLLIMIT) {
        if (stopLoss - price < minDist) {
            stopLoss = price + minDist;
        }
    }
    else if (orderType == OP_BUYSTOP) {
        if (price - stopLoss < minDist) {
            stopLoss = price - minDist;
        }
    }
    else if (orderType == OP_SELLSTOP) {
        if (stopLoss - price < minDist) {
            stopLoss = price + minDist;
        }
    }
    return stopLoss;
}

// given relative stop-loss points, gets the mod stop-loss
// see: https://book.mql4.com/appendix/limits
double _getSLMod(int orderType, double ask, double bid, double dist, double price) {
    if (orderType == OP_BUY) {
        return bid - dist;
    }
    else if (orderType == OP_SELL) {
        return ask + dist;
    }
    else if (orderType == OP_BUYLIMIT) {
        return price - dist;
    }
    else if (orderType == OP_SELLLIMIT) {
        return price + dist;
    }
    else if (orderType == OP_BUYSTOP) {
        return price - dist;
    }
    else if (orderType == OP_SELLSTOP) {
        return price + dist;
    }
    else {
        // should never happen
        return price;
    }
}

// given an absolute take-profit, gets the mod take-profit
// see: https://book.mql4.com/appendix/limits
double _getTPMod(int orderType, double ask, double bid, double minDist, double price, double takeProfit) {
    if (orderType == OP_BUY) {
        if (takeProfit - bid < minDist) {
            takeProfit = bid + minDist;
        }
    }
    else if (orderType == OP_SELL) {
        if (ask - takeProfit < minDist) {
            takeProfit = ask - minDist;
        }
    }
    else if (orderType == OP_BUYLIMIT) {
        if (takeProfit - price < minDist) {
            takeProfit = price + minDist;
        }
    }
    else if (orderType == OP_SELLLIMIT) {
        if (price - takeProfit < minDist) {
            takeProfit = price - minDist;
        }
    }
    else if (orderType == OP_BUYSTOP) {
        if (takeProfit - price < minDist) {
            takeProfit = price + minDist;
        }
    }
    else if (orderType == OP_SELLSTOP) {
        if (price - takeProfit < minDist) {
            takeProfit = price - minDist;
        }
    }
    return takeProfit;
}

// given relative take-profit points, gets the mod take-profit
// see: https://book.mql4.com/appendix/limits
double _getTPMod(int orderType, double ask, double bid, double dist, double price) {
    if (orderType == OP_BUY) {
        return bid + dist;
    }
    else if (orderType == OP_SELL) {
        return ask - dist;
    }
    else if (orderType == OP_BUYLIMIT) {
        return price + dist;
    }
    else if (orderType == OP_SELLLIMIT) {
        return price - dist;
    }
    else if (orderType == OP_BUYSTOP) {
        return price + dist;
    }
    else if (orderType == OP_SELLSTOP) {
        return price - dist;
    }
    else {
        return price;
    }
}

void Do_OrderClose(CJAVal& req) {
    if (!assertParamExists(req, "ticket")) {
        return;
    }
    int ticket = (int)req["ticket"].ToInt();

    if (!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) {
        sendError(StringFormat("Order # %d not found.", ticket));
        return;
    }
    else {
        // order selected
        // use default values if request params were not provided
        double lots = GetDefault(req, "lots", OrderLots());
        double price = GetDefault(req, "price", DefaultClosePrice(OrderSymbol(), OrderType()));
        int slippage = GetDefault(req, "slippage", DefaultSlippage(OrderSymbol()));

        // price & volume normalization
        lots = NormalizeLots(OrderSymbol(), lots);
        price = NormalizePrice(OrderSymbol(), price);
        slippage = NormalizePoints(OrderSymbol(), slippage);

        // open order: close it
        if (!OrderClose(ticket, lots, price, slippage)) {
            // failure
            int errorCode = GetLastError();
            sendError(errorCode, StringFormat("Failed to close order # %d.", ticket));
            return;
        }
        else {
            // success
            sendResponse(StringFormat("Closed order # %d", ticket));
            return;
        }
    }
}

void Do_OrderDelete(CJAVal& req) {
    if (!assertParamExists(req, "ticket")) {
        return;
    }
    int ticket = (int)req["ticket"].ToInt();
    bool closeIfOpened = GetDefault(req, "close_if_opened", false);

    if (!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) {
        sendError(StringFormat("Order # %d not found.", ticket));
        return;
    }
    else {
        // order selected
        if (!OrderDelete(ticket)) {
            // failure
            int errorCode = GetLastError();
            // check if order is open and closing is requested
            if (errorCode == ERR_INVALID_TICKET && !IsPendingOrder(OrderType()) && closeIfOpened) {
                // attempt to close at market price
                req["lots"] = OrderLots();
                req["price"] = DefaultClosePrice(OrderSymbol(), OrderType());
                req["slippage"] = DefaultSlippage(OrderSymbol());
                Do_OrderClose(req);
                return;
            }
            sendError(errorCode, StringFormat("Failed to delete order # %d.", ticket));
            return;
        }
        else {
            // success
            sendResponse(StringFormat("Deleted pending order # %d.", ticket));
            return;
        }
    }
}

void Run_Indicator(CJAVal& req) {
    if (!assertParamExists(req, "indicator") || !assertParamExists(req, "argv") || !assertParamExists(req, "timeout")) {
        return;
    }
    string strIndicator = req["indicator"].ToStr();
    CJAVal argv = req["argv"];
    long timeout = (int)req["timeout"].ToInt();

    // parse indicator function name
    Indicator indicator = (Indicator)-1;
    indicator = StringToEnum(strIndicator, indicator);

    // need to poll, as data may not be immediately available
    int delay = 100; // milliseconds
    long maxTries = timeout / delay;
    bool isDone = false;
    double results = NULL;
    for (int try = 0; try < maxTries && !isDone; try++) {
        results = _runIndicator(indicator, argv);

        // check if function name was recognized
        if (results == NULL) {
            string errorStr = StringFormat("Indicator not recognized: %s.", strIndicator);
            sendError(errorStr);
            return;
        }

        // check for errors
        int errorCode = GetLastError();
        if (errorCode == ERR_HISTORY_WILL_UPDATED) {
            // data not yet loaded; retry until timeout
            isDone = false;
        }
        else if (errorCode != 0) {
            // error occured during indicator run
            sendError(errorCode);
            return;
        }
        else {
            isDone = true;
        }

        if (!isDone) {
            Sleep(delay);
        }
    }
    if (!isDone) {
        sendError("Timed out waiting for indicator data to load.");
        return;
    }
    else {
        sendResponse(results);
        return;
    }
}

double _runIndicator(Indicator indicator, CJAVal& argv) {
    switch(indicator) {
        case iAC:           return iAC(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt());
        case iAD:           return iAD(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt());
        case iADX:          return iADX(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt(), (int)argv[5].ToInt());
        case iAlligator:    return iAlligator(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt(), (int)argv[5].ToInt(), (int)argv[6].ToInt(), (int)argv[7].ToInt(), (int)argv[8].ToInt(), (int)argv[9].ToInt(), (int)argv[10].ToInt(), (int)argv[11].ToInt());
        case iAO:           return iAO(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt());
        case iATR:          return iATR(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt());
        case iBearsPower:   return iBearsPower(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt());
        case iBands:        return iBands(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), argv[3].ToDbl(), (int)argv[4].ToInt(), (int)argv[5].ToInt(), (int)argv[6].ToInt(), (int)argv[7].ToInt());
        case iBullsPower:   return iBullsPower(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt());
        case iCCI:          return iCCI(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt());
        case iDeMarker:     return iDeMarker(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt());
        case iEnvelopes:    return iEnvelopes(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt(), (int)argv[5].ToInt(), argv[6].ToDbl(), (int)argv[7].ToInt(), (int)argv[8].ToInt());
        case iForce:        return iForce(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt(), (int)argv[5].ToInt());
        case iFractals:     return iFractals(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt());
        case iGator:        return iGator(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt(), (int)argv[5].ToInt(), (int)argv[6].ToInt(), (int)argv[7].ToInt(), (int)argv[8].ToInt(), (int)argv[9].ToInt(), (int)argv[10].ToInt(), (int)argv[11].ToInt());
        case iIchimoku:     return iIchimoku(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt(), (int)argv[5].ToInt(), (int)argv[6].ToInt());
        case iBWMFI:        return iBWMFI(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt());
        case iMomentum:     return iMomentum(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt());
        case iMFI:          return iMFI(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt());
        case iMA:           return iMA(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt(), (int)argv[5].ToInt(), (int)argv[6].ToInt());
        case iOsMA:         return iOsMA(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt(), (int)argv[5].ToInt(), (int)argv[6].ToInt());
        case iMACD:         return iMACD(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt(), (int)argv[5].ToInt(), (int)argv[6].ToInt(), (int)argv[7].ToInt());
        case iOBV:          return iOBV(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt());
        case iSAR:          return iSAR(argv[0].ToStr(), (int)argv[1].ToInt(), argv[2].ToDbl(), argv[3].ToDbl(), (int)argv[4].ToInt());
        case iRSI:          return iRSI(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt());
        case iRVI:          return iRVI(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt());
        case iStdDev:       return iStdDev(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt(), (int)argv[5].ToInt(), (int)argv[6].ToInt());
        case iStochastic:   return iStochastic(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt(), (int)argv[4].ToInt(), (int)argv[5].ToInt(), (int)argv[6].ToInt(), (int)argv[7].ToInt(), (int)argv[8].ToInt());
        case iWPR:          return iWPR(argv[0].ToStr(), (int)argv[1].ToInt(), (int)argv[2].ToInt(), (int)argv[3].ToInt());
        default:            return NULL;
    }
}

bool IsValidTradeOperation(int orderType) {
    return (orderType == OP_BUY || orderType == OP_SELL || orderType == OP_BUYLIMIT || orderType == OP_BUYSTOP ||
            orderType == OP_SELLLIMIT || orderType == OP_SELLSTOP);
}

// current market open price, normalized to tick size
double DefaultOpenPrice(string symbol, int orderType) {
    double price = (orderType == OP_BUY || orderType == OP_BUYLIMIT || orderType == OP_BUYSTOP) ?
            MarketInfo(symbol, MODE_ASK) : MarketInfo(symbol, MODE_BID);
    return NormalizePrice(symbol, price);
}

// current market close price, normalized to tick size
double DefaultClosePrice(string symbol, int orderType) {
    double price = (orderType == OP_BUY || orderType == OP_BUYLIMIT || orderType == OP_BUYSTOP) ?
            MarketInfo(symbol, MODE_BID) : MarketInfo(symbol, MODE_ASK);
    return NormalizePrice(symbol, price);
}

// a permissive slippage value: double the spread, in tick size
int DefaultSlippage(string symbol) {
    double tickSize = MarketInfo(symbol, MODE_TICKSIZE);
    double spread = MathAbs(MarketInfo(symbol, MODE_ASK) - MarketInfo(symbol, MODE_BID));
    return int(2.0 * spread / tickSize);
}

// price normalized to tick size; required for prices and sl/tp
double NormalizePrice(string symbol, double price) {
    double tickSize = MarketInfo(symbol, MODE_TICKSIZE);
    return MathRound(price / tickSize) * tickSize;
}

// price normalized to tick size, rounded up; required for stoplevel/freezelevel min-distance calculation
double NormalizePriceUp(string symbol, double price) {
    double tickSize = MarketInfo(symbol, MODE_TICKSIZE);
    return MathCeil(price / tickSize) * tickSize;
}

// points normalized to tick size; required for slippage calculation
int NormalizePoints(string symbol, int points) {
    double pointsPerTick = MarketInfo(symbol, MODE_TICKSIZE) / MarketInfo(symbol, MODE_POINT);
    return int(MathRound(points / pointsPerTick) * pointsPerTick);
}

// volume, normalized to lot step
double NormalizeLots(string symbol, double lots) {
    double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
    double minLot = MarketInfo(symbol, MODE_MINLOT);
    lots = MathRound(lots / lotStep) * lotStep;
    return MathMax(lots, minLot);
}

double PointsToDouble(string symbol, int points) {
    return points * MarketInfo(symbol, MODE_POINT);
}

int DoubleToPoints(string symbol, double val) {
    return (int) MathRound(val / MarketInfo(symbol, MODE_POINT));
}

string BoolToString(bool val) {
    return val ? "true" : "false";
}

string LongToString(long val) {
    return DoubleToStr(val, 0);
}

template<typename T> T StringToEnum(string str, T enumType) {
    for (int i = 0; i < 256; i++) {
        if (str == EnumToString(enumType = (T)i)) {
            return(enumType);
        }
    }
    return -1;
}

template <typename T> void ArrayErase(T& arr[], int index) {
    int last;
    for(last = ArraySize(arr) - 1; index < last; ++index) {
        arr[index] = arr[index + 1];
    }
    ArrayResize(arr, last);
}

template <typename T, typename E> bool ArrayEraseElement(T& arr[], E element) {
    bool elementRemoved = false;
    for (int i = 0; i < ArraySize(arr); ++i) {
        if (arr[i] == element) {
            int index = i;
            int last;
            for(last = ArraySize(arr) - 1; index < last; ++index) {
                arr[index] = arr[index + 1];
            }
            ArrayResize(arr, last);
            elementRemoved = true;
            --i;
        }
    }
    return elementRemoved;
}

bool ArrayContains(CJAVal& arr, string val) {
    for (int i = arr.Size() - 1; i >= 0; --i) {
        string curVal = arr[i].ToStr();
        if (val == curVal) {
            return true;
        }
    }
    return false;
}

void Trace(string msg) {
    if (VERBOSE) {
        Print(msg);
    }
}

bool IsNullOrMissing(CJAVal& obj, string key) {
    if (obj.HasKey(key)) {
        return (obj[key].m_type == jtNULL);
    }
    return true;
}

bool IsPendingOrder(int orderType) {
    return (orderType == OP_BUYLIMIT || orderType == OP_BUYSTOP || orderType == OP_SELLLIMIT || orderType == OP_SELLSTOP);
}

bool GetDefault(CJAVal& obj, string key, bool defaultVal) {
    if (!IsNullOrMissing(obj, key)) {
        return obj[key].ToBool();
    }
    return defaultVal;
}

int GetDefault(CJAVal& obj, string key, int defaultVal) {
    return (int)GetDefault(obj, key, (long)defaultVal);
}

long GetDefault(CJAVal& obj, string key, long defaultVal) {
    if (!IsNullOrMissing(obj, key)) {
        return obj[key].ToInt();
    }
    return defaultVal;
}

double GetDefault(CJAVal& obj, string key, double defaultVal) {
    if (!IsNullOrMissing(obj, key)) {
        return obj[key].ToDbl();
    }
    return defaultVal;
}

string GetDefault(CJAVal& obj, string key, string defaultVal) {
    if (!IsNullOrMissing(obj, key)) {
        return obj[key].ToStr();
    }
    return defaultVal;
}

bool IsRunning() {
    return !IsStopped() && context != NULL;
}

#ifndef __PARSE_FIX_STREAM__
#define __PARSE_FIX_STREAM__

#include <iostream>
#include <iomanip>
#include <fstream>

class Parser {
    //
    enum class state {
        EXPECT_KEY,
        EXPECT_VALUE_INT,
        EXPECT_VALUE_DBL,
        EXPECT_VALUE_CHR,
        EXPECT_VALUE_BOOL,
        EXPECT_VALUE
    } _state = state::EXPECT_KEY;

    static const int nopos = -1;
    static const int buffer_size = 8;

    FIX::Pairs _fix_pair_list;

    char             * _buffer;
    char             * _buffer_build;
    char               _pending_buffer[buffer_size];
    size_t             _pending = 0;

    MessageRoot        _m_root;

    std::ptrdiff_t     _p_buff   = 0;
    std::ptrdiff_t     _c_index  = 0;
    std::ptrdiff_t     _k_value  = 0;

    int    _key       = 0;

    int    _int       = 0;
    long   _lng       = 0L;

    int    _fact      = 0;
    int    _dec       = 0;

    char   _char      = '\0';

    bool   _is_ready  = false;

    FIX::Messages::msg_u_t  _msg;

    int error         = 0;
public:
    
    Parser(char * buffer, char * buffer_build) {
        _buffer = buffer;
        _buffer_build = buffer_build;
    }

    int tryx(char * c, int & beg, size_t & s) {
        int idx = nopos, dot_idx = nopos;
        switch(_state) {
        case state::EXPECT_KEY:
            idx = find_index(c, beg, s, '=');
            //std::cout << "IDX=" << idx << std::endl;

            clog("BEG=%d, IDX=%d", beg, idx);
            if (idx == nopos) idx = s;
            make_int(_key, c, beg, idx);

            clog("KEY=%4d BEG=%d, IDX=%d", _key, beg, idx);

            if (idx != s) {
                _state = state::EXPECT_VALUE;
                if (_key == 0)
                    return FIX::Error::Parse::no_key; // no key
                switch (_key) {
                case_field_type_int:
                    //std::cout << "KEY INT -> " << _key << ">" << std::endl;
                    _state = state::EXPECT_VALUE_INT;
                    _int = 0;
                    break;
                case_field_type_long:
                    //std::cout << "KEY DBL -> " << _key << ">" << std::endl;
                    _state = state::EXPECT_VALUE_DBL;
                    //_fact = _int = 0;
                    _fact = _lng = 0;
                    break;
                case_field_type_char:
                    //std::cout << "KEY CHR -> " << _key << ">" << std::endl;
                    _state = state::EXPECT_VALUE_CHR;
                    _char = '\0';
                    break;
                case_field_type_boolean:
                    //std::cout << "KEY BOL -> " << _key << ">" << std::endl;
                    _state = state::EXPECT_VALUE_BOOL;
                    _char = '\0';
                    break;
                default:
                    //std::cout << "KEY STR -> <" << _key << ">" << std::endl;
                    _state = state::EXPECT_VALUE;
                    break;
                }
            }

            beg = idx + 1;
            break;
        case state::EXPECT_VALUE_INT:
            clog("BEG=%3d SIZE=%d", beg, s);
            idx = find_index(c, beg, s, 1);
            clog("KEY=%4d IDX=%d", _key, idx);
            if (idx == nopos) idx = s;
            else _state = state::EXPECT_KEY;
            make_int(_int, c, beg, idx);
            beg = idx + 1;
            if (idx != s) {
                _fix_pair_list.push(_key, _int);
                _key = _int = 0;
            }
            break;
        case state::EXPECT_VALUE_DBL:
            clog("BEG=%3d SIZE=%d", beg, s);
            idx = find_index(c, beg, s, 1, '.', dot_idx);
            clog("KEY=%4d DOT_IDX=%d, IDX=%d LONG=%ld FACT=%d",
                 _key, dot_idx, idx, _lng, _fact);
            if (idx == nopos) idx = s;
            else _state = state::EXPECT_KEY;
            make_dbl(_lng, c, beg, idx, dot_idx);
            clog("BEG=%3d SIZE=%d LONG=%ld FACT=%d", beg, s, _lng, _fact);
            beg = idx + 1;
            if (idx != s) {
                _lng <<= 4; _lng += _fact;
                _fix_pair_list.push(_key, _lng);
                _key = _lng = _fact = 0;
            }
            break;
        case state::EXPECT_VALUE_CHR:
            clog("BEG=%3d SIZE=%d", beg, s);
            idx = find_index(c, beg, s, 1);
            clog("KEY=%4d IDX=%d", _key, idx);
            if (idx == nopos) idx = s;
            else _state = state::EXPECT_KEY;
            make_char(_char, c, beg, idx);
            beg = idx + 1;
            if (idx != s) {
                _fix_pair_list.push(_key, _char);
                _key = 0; _char = '\0';
            }
            break;
        case state::EXPECT_VALUE_BOOL:
            clog("BEG=%3d SIZE=%d", beg, s);
            idx = find_index(c, beg, s, 1);
            clog("KEY=%4d IDX=%d", _key, idx);
            if (idx == nopos) idx = s;
            else _state = state::EXPECT_KEY;
            make_char(_char, c, beg, idx);
            beg = idx + 1;
            if (idx != s) {
                short _bool = 0; // unset
                switch(_char) {
                case 'Y': _bool = 3; break;
                case 'N': _bool = 2; break;
                default: return FIX::Error::Parse::unexpected_bool_char;
                }
                _fix_pair_list.push(_key, _bool);
                _key = 0; _char = '\0';
            }
            break;
        default:
        case state::EXPECT_VALUE:
            clog("BEG=%3d SIZE=%d", beg, s);
            idx = find_index(c, beg, s, 1);
            clog("KEY=%4d IDX=%d", _key, idx);
            if (idx == nopos) idx = s;
            else _state = state::EXPECT_KEY;
            make_str(_buffer, _p_buff, c, beg, idx);
            beg = idx + 1;
            clog("BEG=%3d SIZE=%d", beg, s);
            if (idx != s) {
                _p_buff++;
                if (_key == 10) {
                    _is_ready = true;
                    for(int i = beg; i < s; i++)
                        _pending_buffer[i-beg] = c[i];
                    _pending = s - beg; // ignore \0
                    _pending_buffer[s - beg] = '\0';

                    clog("PENDING=<%s>", _pending_buffer);
                } else if (_key == 35) {
                    _k_value = _c_index;
                }

                clog("KEY=%4d VAL=<%s>", _key, _buffer + _c_index);
                /*
                  std::cout << "<<<<< KEY=" << _key
                  << " VAL=<" << _buffer + _c_index << ">"
                  << std::endl;
                */
                _fix_pair_list.push(_key, _c_index);
                _c_index = _p_buff;
                _key = 0;
            }
            break;
        }
        return 0;
    }
    
    int push(char _c[buffer_size], size_t _s) {

        char X[buffer_size + 1] = {_c[0], _c[1], _c[2], _c[3], _c[4], _c[5], _c[6], _c[7],  0};
        clog("NEW MSG=<%s>", X);

        int idx = nopos, sbeg = 0, pbeg = 0, dot_idx = nopos;
        size_t _l_pending = _pending;

        if (_pending > 0) {
            clog("PEN MSG=<%s>", _pending_buffer);
            _pending = 0;
        }

        int err = 0;

        while (true && err == 0) {
            clog("PENDING = %2d, PBEG = %2d, NEW - SIZE = %2d, SBEG = %2d", _l_pending, pbeg, _s, sbeg);

            int & beg  = (pbeg < _l_pending) ? pbeg : sbeg;
            size_t & s = (pbeg < _l_pending) ? _l_pending: _s;

            // char *  c = (pbeg < _l_pending) ? _pending_buffer : _c;

            if (sbeg >= _s) break;
            if (pbeg < _l_pending) {
                err = tryx(_pending_buffer, beg, s);
            } else {
                err = tryx(_c, beg, s);
            }
        }

        return err;
    }

    bool isMessageReady() {
        return _is_ready;
    }

    void dumpMessage() {
        using namespace std;
        size_t pcount = _fix_pair_list.getSize();
        const FIX::Pairs::fix_pair_t * pairs = _fix_pair_list.getPairs();
        cout << "PAIR COUNT = " << pcount << endl;
        for(int i = 0; i < pcount; i++) {
            int key = pairs[i].first;

            cout << "KEY = " << key << " VAL - = <";
            switch (key) {
            case_field_type_int:
                cout << "INT:" << get<int>(pairs[i].second) << ">" << endl;
                break;
            case_field_type_long:
                cout << "DBL:" << get<long>(pairs[i].second) << ">" << endl;
                break;
            case_field_type_char:
                cout << "CHR:" << get<char>(pairs[i].second) << ">" << endl;
                break;
            case_field_type_boolean:
                cout << "BOL:" << get<short>(pairs[i].second) << ">" << endl;
                break;
            default:
                //std::cout << "K=" << _key << " - cindx " << get<int>(pairs[i].second) << std::endl;
                cout << "STR:" << _buffer + get<int>(pairs[i].second) << ">" << endl;
            }
        }
    }

#define case_builder(__msg_type__)                                      \
    case FIX::Messages::__msg_type__::type_id: {                        \
        FIX::Messages::__msg_type__ p;                                  \
        p.init(_buffer);                                                \
        p.init_1(_buffer);                                              \
        p.init_2(_buffer);                                              \
        p.init_3(_buffer);                                              \
        err = p.buildFromPairs(_fix_pair_list);                         \
        p.show();                                                       \
        if (validate(p) != 0) {                                         \
            std::cout << "Message Dropped   <" << _buffer + _k_value << ">" << std::endl; \
            err = 1; break;                                             \
        } else {                                                        \
            /* char * x = p.encode(_buffer_build); */                   \
            std::cout << "Message Validated <" << _buffer + _k_value    \
                      << "> <" << "x" << ">" << std::endl;              \
        }                                                               \
    }                                                                   \
    break;

int processMessage() {
        int err = 0;
        switch (msg_type_key(_buffer + _k_value)) {
            // case_builder(Advertisement);
            // case_builder(AllocationInstruction);
            // case_builder(AllocationInstructionAck);
            // case_builder(AllocationReport);
            // case_builder(AllocationReportAck);
            // case_builder(AssignmentReport);
            // case_builder(BidRequest);
            // case_builder(BidResponse);
            // case_builder(BusinessMessageReject);
            // case_builder(CollateralAssignment);
            // case_builder(CollateralInquiry);
            // case_builder(CollateralInquiryAck);
            // case_builder(CollateralReport);
            // case_builder(CollateralRequest);
            // case_builder(CollateralResponse);
            // case_builder(Confirmation);
            // case_builder(ConfirmationAck);
            // case_builder(ConfirmationRequest);
            // case_builder(CrossOrderCancelReplaceRequest);
            // case_builder(CrossOrderCancelRequest);
            // case_builder(DerivativeSecurityList);
            // case_builder(DerivativeSecurityListRequest);
            // case_builder(DontKnowTrade);
            // case_builder(Email);
            // case_builder(ExecutionReport);
            case_builder(Heartbeat);
            case_builder(IOI);
            // case_builder(ListCancelRequest);
            // case_builder(ListExecute);
            // case_builder(ListStatus);
            // case_builder(ListStatusRequest);
            // case_builder(ListStrikePrice);
            case_builder(Logon);
            case_builder(Logout);
            // case_builder(MarketDataIncrementalRefresh);
            // case_builder(MarketDataRequest);
            // case_builder(MarketDataRequestReject);
            // case_builder(MarketDataSnapshotFullRefresh);
            // case_builder(MassQuote);
            // case_builder(MassQuoteAcknowledgement);
            // case_builder(MultilegOrderCancelReplace);
            // case_builder(NetworkCounterpartySystemStatusRequest);
            // case_builder(NetworkCounterpartySystemStatusResponse);
            // case_builder(NewOrderCross);
            // case_builder(NewOrderList);
            // case_builder(NewOrderMultileg);
            case_builder(NewOrderSingle);
            // case_builder(News);
            // case_builder(OrderCancelReject);
            // case_builder(OrderCancelReplaceRequest);
            case_builder(OrderCancelRequest);
            // case_builder(OrderMassCancelReport);
            // case_builder(OrderMassCancelRequest);
            // case_builder(OrderMassStatusRequest);
            // case_builder(OrderStatusRequest);
            // case_builder(PositionMaintenanceReport);
            // case_builder(PositionMaintenanceRequest);
            // case_builder(PositionReport);
            // case_builder(Quote);
            // case_builder(QuoteCancel);
            // case_builder(QuoteRequest);
            // case_builder(QuoteRequestReject);
            // case_builder(QuoteResponse);
            // case_builder(QuoteStatusReport);
            // case_builder(QuoteStatusRequest);
            // case_builder(RFQRequest);
            // case_builder(RegistrationInstructions);
            // case_builder(RegistrationInstructionsResponse);
            // case_builder(Reject);
            // case_builder(RequestForPositions);
            // case_builder(RequestForPositionsAck);
            // case_builder(ResendRequest);
            // case_builder(SecurityDefinition);
            // case_builder(SecurityDefinitionRequest);
            // case_builder(SecurityList);
            // case_builder(SecurityListRequest);
            // case_builder(SecurityStatus);
            // case_builder(SecurityStatusRequest);
            // case_builder(SecurityTypeRequest);
            // case_builder(SecurityTypes);
            // case_builder(SequenceReset);
            // case_builder(SettlementInstructionRequest);
            // case_builder(SettlementInstructions);
            // case_builder(TestRequest);
            // case_builder(TradeCaptureReport);
            // case_builder(TradeCaptureReportAck);
            // case_builder(TradeCaptureReportRequest);
            // case_builder(TradeCaptureReportRequestAck);
            // case_builder(TradingSessionStatus);
            // case_builder(TradingSessionStatusRequest);
            // case_builder(UserRequest);
            // case_builder(UserResponse);
            // case_builder(XMLnonFIX);
        default:
            std::cout << "Unhandled Message <" << _buffer + _k_value << ">" << std::endl;
            err = 1;
        }
        
        return err;
    }

    void resetParsing () {
        _c_index = _p_buff = 0;
        _key = 0;
        _fix_pair_list.reset();
        _is_ready = false;
        _state = state::EXPECT_KEY;
    }

private:

};

#endif //__PARSE_FIX_STREAM__

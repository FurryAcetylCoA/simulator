%{
  #include <iostream>
  #include "common.h"
  #include "syntax.hh"
  #include "Parser.h"
  std::string no_name{};
int p_stoi(std::string str); // 为啥parser有一个专门的stoi
//   int  yylex (yy::parser::value_type* yylval);
%}

%language "c++"
%require "3.8"

%define api.parser.class {Syntax}
%define api.namespace {Parser}
%define api.value.type variant

%define parse.error verbose
%parse-param {Lexical* scanner}

%code requires
{
    namespace Parser {
        class Lexical;
    } // namespace calc
}

%code
{
    #define synlineno() scanner->lineno()
    #define yylex(x) scanner->lex(x)
    // #define yylex(x) scanner->lex_debug(x)
}

%destructor { $$.release(); } <std::unique_ptr<PNode>> <std::unique_ptr<PList>>

/* token */
%token DoubleLeft "<<"
%token DoubleRight ">>"
%token <std::string> ID INT RINT String
%token <std::string> Clock Reset IntType anaType FixedType AsyReset Probe ProbeType
%token <std::string> E2OP E1OP E1I1OP E1I2OP
%token <std::string> Ruw
%token <std::string> Info
%token Flip Mux Validif Invalidate Mem SMem CMem Wire Reg RegReset Inst Of Node Attach
%token When Else Stop Printf Skip Input Output Assert
%token Module Extmodule Defname Parameter Intmodule Intrinsic Circuit Connect Public
%token Define Const
%token Firrtl Version INDENT DEDENT
%token RightArrow "=>"
%token Leftarrow "<-"
%token DataType Depth ReadLatency WriteLatency ReadUnderwrite Reader Writer Readwriter Write Read Infer Rdwr Mport
/* internal node */
%type <int> width
%type <std::unique_ptr<PList>> cir_mods fields params
%type <std::unique_ptr<PNode>> module extmodule ports statements port type statement when_else param exprs
%type <std::unique_ptr<PNode>> chirrtl_memory chirrtl_memory_datatype chirrtl_memory_port
%type <std::unique_ptr<PNode>> reference expr primop_2expr primop_1expr primop_1expr1int primop_1expr2int
%type <std::unique_ptr<PNode>> field type_aggregate type_ground circuit
%type <std::string> info ALLID ext_defname

%nonassoc LOWER_THAN_ELSE
%nonassoc Else


%%
/* remove version */
circuit: version Circuit ALLID ':' annotations info INDENT cir_mods DEDENT { $$ = newNode(P_CIRCUIT, synlineno(), $3, $6 ); scanner->root = std::move($$); scanner->list = std::move($8); (void)yynerrs_;}
  | INDENT cir_mods DEDENT { scanner->list = std::move($2); }
  ;
ALLID: ID {$$ = $1; }
    | Inst { $$ = "inst"; }
    | Printf { $$ = "printf"; }
    | Assert { $$ = "assert"; }
    | Mem { $$ = "mem"; }
    | Of { $$ = "of"; }
    | Reg { $$ = "reg"; }
    | Input { $$ = "input"; }
    | Output { $$ = "output"; }
    | Invalidate { $$ = "invalidate"; }
    | Mux { $$ = "mux"; }
    | Stop { $$ = "stop"; }
    | Depth {$$ = "depth"; }
    | Skip {$$ = "skip"; }
    | Write {$$ = "write"; }
    | Writer {$$ = "writer"; }
    | Read {$$ = "read"; }
    | Reader {$$ = "reader"; }
    | Version {$$ = "version"; }
    | Probe {$$ = "probe"; }
    | Module { $$ = "module"; }
    | Const { $$ = "const"; }
    ;
/* Fileinfo communicates Chisel source file and line/column info */
/* linecol: INT ':' INT    { $$ = malloc(strlen($1) + strlen($2) + 2); strcpy($$, $1); str$1 + ":" + $3}
    ; */
info:               { $$ = "";}
    | Info          { $$ = $1;}
    ;
/* type definition */
width:                { $$ = -1; } /* infered width */
    | '<' INT '>'     { $$ = p_stoi($2); }
    ;
binary_point:
    | "<<" INT ">>"   { TODO(); }
    ;
type_ground: Clock              { $$ = newNode(P_Clock, synlineno()); }
    | Reset                     { $$ = newNode(P_RESET, synlineno()); $$->setWidth(1); $$->setSign(0);}
    | AsyReset                  { $$ = newNode(P_ASYRESET, synlineno()); $$->setWidth(1); $$->setSign(0);}
    | IntType width             { $$ = newNode(P_INT_TYPE, synlineno(), $1); $$->setWidth($2); $$->setSign($1[0] == 'S'); }
    | ProbeType '<' IntType '>' { $$ = newNode(P_INT_TYPE, synlineno(), $3); $$->setWidth(-1); $$->setSign($3[0] == 'S'); }
    | ProbeType '<' IntType width '>' { $$ = newNode(P_INT_TYPE, synlineno(), $3); $$->setWidth($4); $$->setSign($3[0] == 'S'); }
    | ProbeType '<' IntType '<' INT ">>" { $$ = newNode(P_INT_TYPE, synlineno(), $3); $$->setWidth(p_stoi($5)); $$->setSign($3[0] == 'S'); }
    | anaType width             { TODO(); }
    | FixedType width binary_point  { TODO(); }
    ;
fields:                 { $$ = std::make_unique<PList>(); }
    | fields ',' field  { $$ = std::move($1); $$->append(std::move($3)); }
    | field             { $$ = std::make_unique<PList>(std::move($1)); }
    ;
type_aggregate: '{' fields '}'  { $$ = newNode(P_AG_FIELDS, synlineno()); $$->appendChildList($2); }
    | type '[' INT ']'          { $$ = newNode(P_AG_ARRAY, synlineno(), no_name, std::move($1)); $$->appendExtraInfo(std::move($3)); }
    ;
field: ALLID ':' type { $$ = newNode(P_FIELD, synlineno(), $1, std::move($3)); }
    | Flip ALLID ':' type  { $$ = newNode(P_FLIP_FIELD, synlineno(), $2, std::move($4)); }
    ;
type: type_ground  { $$ = std::move($1); }
    | Const type_ground  { $$ = std::move($2); }
    | type_aggregate { $$ = std::move($1); }
    | Const type_aggregate { $$ = std::move($2); }
    ;
/* primitive operations */
primop_2expr: E2OP expr ',' expr ')' { $$ = newNode(P_2EXPR, synlineno(), $1, std::move($2), std::move($4)); }
    ;
primop_1expr: E1OP expr ')' { $$ = newNode(P_1EXPR, synlineno(), $1, std::move($2)); }
    ;
primop_1expr1int: E1I1OP expr ',' INT ')' { $$ = newNode(P_1EXPR1INT, synlineno(), $1, std::move($2)); $$->appendExtraInfo($4); }
    ;
primop_1expr2int: E1I2OP expr ',' INT ',' INT ')' { $$ = newNode(P_1EXPR2INT, synlineno(), $1, std::move($2)); $$->appendExtraInfo($4); $$->appendExtraInfo($6); }
    ;
/* expression definitions */
exprs:                  { $$ = newNode(P_EXPRS, synlineno());}
    | exprs ',' expr    { $$ = std::move($1); $$->appendChild(std::move($3)); }
    ;
expr: IntType width '(' ')'     { $$ = newNode(P_EXPR_INT_NOINIT, synlineno(), $1); $$->setWidth($2); $$->setSign($1[0] == 'S');}
    | IntType width '(' INT ')' { $$ = newNode(P_EXPR_INT_INIT, synlineno(), $1); $$->setWidth($2); $$->setSign($1[0] == 'S'); $$->appendExtraInfo($4);}
    | IntType width '(' RINT ')'{ $$ = newNode(P_EXPR_INT_INIT, synlineno(), $1); $$->setWidth($2); $$->setSign($1[0] == 'S'); $$->appendExtraInfo($4);}
    | reference { $$ = std::move($1); }
    | Mux '(' expr ',' expr ',' expr ')' { $$ = newNode(P_EXPR_MUX, synlineno(), no_name, std::move($3), std::move($5), std::move($7)); }
    | Validif '(' expr ',' expr ')' { $$ = std::move($5); }
    | primop_2expr  { $$ = std::move($1); }
    | primop_1expr  { $$ = std::move($1); }
    | primop_1expr1int  { $$ = std::move($1); }
    | primop_1expr2int  { $$ = std::move($1); }
    ;
reference: ALLID  { $$ = newNode(P_REF, synlineno(), $1); }
    | reference '.' ALLID    { $$ = std::move($1); $$->appendChild(newNode(P_REF_DOT, synlineno(), $3)); }
    | reference '[' INT ']'  { $$ = std::move($1); $$->appendChild(newNode(P_REF_IDX_INT, synlineno(), $3)); }
    | reference '[' expr ']' { $$ = std::move($1); $$->appendChild(newNode(P_REF_IDX_EXPR, synlineno(), no_name, std::move($3))); }
    ;

/* CHIRRTL Memory */
chirrtl_memory_datatype: type { $$ = newNode(P_DATATYPE, synlineno(), no_name, std::move($1)); }
                       ;

chirrtl_memory : SMem ALLID ':' chirrtl_memory_datatype Ruw info            { $$ = newNode(P_SEQ_MEMORY , synlineno(), /*name*/$2, /*info*/$6, /* DataType */ std::move($4)); $$->appendExtraInfo($5); }
               | SMem ALLID ':' chirrtl_memory_datatype info                { $$ = newNode(P_SEQ_MEMORY , synlineno(), /*name*/$2, /*info*/$5, /* DataType */ std::move($4)); }
               | CMem ALLID ':' chirrtl_memory_datatype info                { $$ = newNode(P_COMB_MEMORY, synlineno(), /*name*/$2, /*info*/$5, /* DataType */ std::move($4)); }
               ;

chirrtl_memory_port: Write Mport ALLID '=' ALLID '[' expr ']' ',' expr info { $$ = newNode(P_WRITE, synlineno(), /* Name */ $3, /* Info */ $11, /* Addr */ std::move($7), /* clock */ std::move($10)); $$->appendExtraInfo(/* MemName */$5); }
                   | Read  Mport ALLID '=' ALLID '[' expr ']' ',' expr info { $$ = newNode(P_READ , synlineno(), /* Name */ $3, /* Info */ $11, /* Addr */ std::move($7), /* clock */ std::move($10)); $$->appendExtraInfo(/* MemName */$5); }
                   | Infer Mport ALLID '=' ALLID '[' expr ']' ',' expr info { $$ = newNode(P_INFER, synlineno(), /* Name */ $3, /* Info */ $11, /* Addr */ std::move($7), /* clock */ std::move($10)); $$->appendExtraInfo(/* MemName */$5); }
                   | Rdwr Mport ALLID '=' ALLID '[' expr ']' ',' expr info  { $$ = newNode(P_READWRITER, synlineno(), /* Name */ $3, /* Info */ $11, /* Addr */ std::move($7), /* clock */ std::move($10)); $$->appendExtraInfo(/* MemName */$5); }
                   ;

/* statements */
references:
    | references reference { TODO(); }
    ;
statements: { $$ = newNode(P_STATEMENTS, synlineno()); }
    | statements statement { $$ = std::move($1); $$->appendChild(std::move($2)); }
    ;
when_else:  %prec LOWER_THAN_ELSE { $$ = newNode(P_STATEMENTS, synlineno()); }
    | Else ':' INDENT statements DEDENT { $$ = std::move($4); }
    ;
statement: Wire ALLID ':' type info    { $$ = newNode(P_WIRE_DEF, $4->lineno, $2, $5, std::move($4)); }
    | Reg      ALLID ':' type ',' expr info  { $$ = newNode(P_REG_DEF, $4->lineno, /* name */$2, /* info */$7 , /* Type */std::move($4), /* Clock */std::move($6)); }
    | RegReset ALLID ':' type ',' expr ',' expr ',' expr info { $$ = newNode(P_REG_RESET_DEF, $4->lineno, /* name */$2, /* info */$11, /* Type */ std::move($4), /* Clock */ std::move($6), /* Reset Cond */ std::move($8), /* Reset Val*/ std::move($10)); }
    | chirrtl_memory      { $$ = std::move($1); }
    | chirrtl_memory_port { $$ = std::move($1); }
    | Inst ALLID Of ALLID info    { $$ = newNode(P_INST, synlineno(), $2, $5); $$->appendExtraInfo($4); }
    | Node ALLID '=' expr info { $$ = newNode(P_NODE, synlineno(), $2, $5, std::move($4)); }
    | Connect reference ',' expr info { $$ = newNode(P_CONNECT, $2->lineno, no_name, $5, std::move($2), std::move($4)); }
    | Connect reference ',' Read '(' expr ')' info { $$ = newNode(P_CONNECT, $2->lineno, no_name, $8, std::move($2), std::move($6)); }
    | reference "<-" expr info  { $$ = newNode(P_PAR_CONNECT, $1->lineno, no_name, $4, std::move($1), std::move($3)); }
    | Invalidate reference info { $$ = newNode(P_INVALID, synlineno()); $$->setWidth(1); $$ = newNode(P_CONNECT, $2->lineno, no_name, $3, std::move($2), std::move($$)); }
    | Define reference '=' Probe '(' expr ')' info { $$ = newNode(P_CONNECT, synlineno(), no_name, $8, std::move($2), std::move($6)); }
    | Define reference '=' expr info { $$ = newNode(P_CONNECT, synlineno(), no_name, $5, std::move($2), std::move($4)); }
    | Attach '(' references ')' info { TODO(); }
    | When expr ':' info INDENT statements DEDENT when_else   { $$ = newNode(P_WHEN, $2->lineno, no_name, $4, std::move($2), std::move($6), std::move($8)); } /* expected newline before statement */
    | Stop '(' expr ',' expr ',' INT ')' info   { $$ = newNode(P_STOP, synlineno(), no_name, $9, std::move($3), std::move($5)); $$->appendExtraInfo($7); }
    | Stop '(' expr ',' expr ',' INT ')' ':' ALLID info   { $$ = newNode(P_STOP, synlineno(), $10, $11, std::move($3), std::move($5)); $$->appendExtraInfo($7); }
    | Printf '(' expr ',' expr ',' String exprs ')' ':' ALLID info { $$ = newNode(P_PRINTF, synlineno(), $11, $12, std::move($3), std::move($5), std::move($8)); $$->appendExtraInfo($7); }
    | Printf '(' expr ',' expr ',' String exprs ')' info    { $$ = newNode(P_PRINTF, synlineno(), no_name, $10, std::move($3), std::move($5), std::move($8)); $$->appendExtraInfo($7); }
    | Assert '(' expr ',' expr ',' expr ',' String ')' ':' ALLID info { $$ = newNode(P_ASSERT, synlineno(), $12, $13, std::move($3), std::move($5), std::move($7)); $$->appendExtraInfo($9); }
    | Assert '(' expr ',' expr ',' expr ',' String ')' info { $$ = newNode(P_ASSERT, synlineno(), no_name, $11, std::move($3), std::move($5), std::move($7)); $$->appendExtraInfo($9); }
    | Skip info { $$ = NULL; }
    ;
/* module definitions */
port: Input ALLID ':' type info    { $$ = newNode(P_INPUT,  synlineno(), $2, $5, std::move($4)); }
    | Output ALLID ':' type info   { $$ = newNode(P_OUTPUT, synlineno(), $2, $5, std::move($4)); }
    ;
ports:  { $$ =  std::make_unique<PNode>(P_PORTS); }
    | ports port    { $$ = std::move($1); $$->appendChild(std::move($2)); }
    ;
opt_public:   {}
    | Public  {}
    ;
module: opt_public Module ALLID ':' info INDENT ports statements DEDENT { $$ = newNode(P_MOD, synlineno(), $3, $5, std::move($7), std::move($8)); }
    ;
ext_defname:                       { $$ = ""; }
    | Defname '=' ALLID            { $$ = $3; }
    ;
params:                            { $$ = std::make_unique<PList>(); }
    | params param                 { $$ = std::move($1); $$->append(std::move($2)); }
    ;
param: Parameter ALLID '=' String  {  }
    | Parameter ALLID '=' INT      {  }
    ;
extmodule: Extmodule ALLID ':' info INDENT ports ext_defname params DEDENT  { $$ = newNode(P_EXTMOD, synlineno(), $2, $4, std::move($6)); $$->appendExtraInfo($7); }
    ;
intmodule: Intmodule ALLID ':' info INDENT ports Intrinsic '=' ALLID params DEDENT	{ TODO(); }
		;
/* in-line anotations */
member:
      String ':' String {}
    | String ':' ALLID {}
    | String ':' INT {}
    | String ':' json {}
    | String ':' json_array {}
    ;
members:
    | member             {}
    | member ',' members {}
    ;
Strings: String             {}
    | String ',' Strings     {}
    ;
json: '{' '}'  {}
    | '{' INDENT members DEDENT '}' {}
    | '[' INDENT Strings DEDENT ']' {}
    ;
jsons: json            {}
     | json ',' jsons  {}
     ;
json_array: '[' INDENT jsons DEDENT ']' { }
		;
annotations: 
		| '%' '[' json_array ']' { }
		;
/* version definition */
version: Firrtl Version INT '.' INT '.' INT { }
		;
cir_mods:                       { $$ = std::make_unique<PList>(); }
		| cir_mods module       { $$ = std::move($1); $$->append(std::move($2)); }
		| cir_mods extmodule    { $$ = std::move($1); $$->append(std::move($2)); }
		| cir_mods intmodule    { TODO(); } // TODO
		;

%%

void Parser::Syntax::error(const std::string& msg) {
    auto Line = scanner->lineno();
    auto UnexpectedToken = std::string(scanner->YYText());
    std::cerr << "Error at line " << Line << ": " << msg 
          << " (unexpected token: '" << UnexpectedToken << "')." << std::endl;
    exit(EXIT_FAILURE);
}

/*
Generate design graph (the intermediate representation of the input circuit) from JSON
*/

#include "common.h"
#include "json.hpp"
#include <fstream>

using json = nlohmann::json;

// Helper functions
void updatePrevNext(Node* n);
int p_stoi(const char* str);
// Maps from util.cpp
extern std::map<std::string, OPType> expr2Map;
extern std::map<std::string, OPType> expr1int1Map;
// A map between node name:string and node:Node, for reference
static std::map<std::string, Node*> allSignals;

static ASTExpTree* visitJExpr(const json &J);

static void addSignal(const std::string& s, Node* n) {
  Assert(allSignals.find(s) == allSignals.end(), "Signal %s is already in allSignals\n", s.c_str());
  allSignals[s] = n;
  printf("add signal %s\n", s.c_str());
}
static Node* getSignal(const std::string& s) {
  Assert(allSignals.find(s) != allSignals.end(), "Signal %s is not in allSignals\n", s.c_str());
  return allSignals[s];
}

// {"op": "ref", "ref_id": NAME}
static ASTExpTree * visitJRef(const json &J) {
  Assert(J["ref_id"].is_string(), "ref id is not a string");
  auto* ret = new ASTExpTree(false);
  ret->getExpRoot()->setNode(getSignal(J.at("ref_id")));

  return ret;
}

//{"op": "const", "value": VALUE, "width": WIDTH, "sign": SIGN}
static ASTExpTree* visitConst(const json &J){
  Assert(J["width"].is_number() && J["value"].is_string(), "width is not a number or value is not a string");
  Assert(J["sign"].is_boolean() , "sign is not a boolean");

  auto* ret = new ASTExpTree(false);
  ret->getExpRoot()->strVal = J["value"];
  ret->setType(J["width"], J["sign"]? 1 : 0);
  ret->setOp(OP_INT);
  return ret;
}

static ASTExpTree* visitMux(const json &J) {
  Assert(J["args"].is_array() && J["args"].size() == 3, "malformed mux");
  ASTExpTree* cond = visitJExpr(J["args"].at(0));
  ASTExpTree* left = visitJExpr(J["args"].at(1));
  ASTExpTree* right = visitJExpr(J["args"].at(2));

  ASTExpTree* ret = left->dupEmpty();
  ret->setOp(OP_MUX);
  ret->addChildSameTree(cond);
  ret->addChildTree(2, left, right);

  delete cond;
  delete left;
  delete right;

  return ret;
}

static ASTExpTree* visitOP2Expr(const json &J) {
  Assert(J["args"].is_array() && J["args"].size() == 2 ,"Malformed op2");
  ASTExpTree* op1 = visitJExpr(J["args"].at(0));
  ASTExpTree* op2 = visitJExpr(J["args"].at(1));

  auto* ret = new ASTExpTree(false);
  ret->setOp(str2op_expr2(J["op"]));
  ret->addChildTree(2, op1, op2);

  delete op1;
  delete op2;
  return ret;
}

static ASTExpTree* visitOP1Int1Expr(const json &J) {
  Assert(J.contains("args") && J["args"].is_array() && J["args"].size() == 2 ,"Malformed op2");
  ASTExpTree* op1 = visitJExpr(J["args"].at(0));

  auto* ret = new ASTExpTree(false);
  ret->setOp(str2op_expr1int1(J["op"]));
  ret->addChildTree(1, op1);
  ret->addVal(p_stoi(std::string(J["args"].at(1)).c_str()));

  delete op1;
  return ret;
}

static ASTExpTree* visitJExpr(const json &J) {
  Assert(!J.is_null() && !J["op"].is_null(), "Empty json object");// second might changed to contains()
  ASTExpTree* ret = nullptr;
  if (J["op"] == "ref") {
    ret = visitJRef(J);
  }else if (J["op"] == "const") {
    ret = visitConst(J);
  }else if (J["op"] == "mux") {
    ret = visitMux(J);
  }else if (expr2Map.find(J["op"]) != expr2Map.end()) {
    ret = visitOP2Expr(J);
  }else if (expr1int1Map.find(J["op"]) != expr1int1Map.end()) {
    ret = visitOP1Int1Expr(J);
  }
  else {
    printf("Unknown op\n");
    Panic();
  }
  return ret;
}

// In json mode. Every entry is a node
static Node* visitJEntry(const json &J, graph* g) {
  Assert(!J.is_null(), "Empty json object");

  Node* node = nullptr;

  if (J.contains("io")) {
    if (J["io"] == "i") {
      // Input node doesn't have a valTree
      node = new Node(NODE_INP);
      node->width = J["width"];
      node->sign = J["sign"];
      g->input.push_back(node);
    }else if (J["io"] == "o") {
      node = new Node(NODE_OUT);
      ASTExpTree* exp = nullptr;
      exp = visitJExpr(J);
      node->valTree = new ExpTree(exp->getExpRoot(), node);
      g->output.push_back(node);
    }else Panic();
  }else {
    ASTExpTree* exp = nullptr;
    exp = visitJExpr(J);
    node = new Node(NODE_OTHERS);
    node->valTree = new ExpTree(exp->getExpRoot(), node);
  }
  node->name = J["id"];
  return node;
}

graph* JSON2Graph(const char *InputFileName) {
  graph* g = new graph();
  g->name = "jsonCir";
  std::ifstream f(InputFileName);
  json data = json::parse(f);
  Assert(data.contains("design"), "Json provided is malformed");
  for (auto& element : data["design"]) {
    auto node = visitJEntry(element,g);
    addSignal(node->name, node);
  }
  //convert to SN and construct graph
  for (auto& [_,node]: allSignals) {
    if (node->valTree) {
      node->assignTree.push_back(node->valTree);
      node->valTree = nullptr;
    }
    updatePrevNext(node);
  }
  for (auto & [_,node] : allSignals) {
    node->constructSuperNode();
  }
  /* must be called after constructSuperNode all finished */
  for (auto & [_,node] : allSignals) {
    node->constructSuperConnect();
  }
  for (Node* input : g->input) {
    g->supersrc.push_back(input->super);
    for (ExpTree* tree : input->assignTree) Assert(tree->isInvalid(), "input %s not invalid", input->name.c_str());
    input->assignTree.clear();
  }

  for (auto [_, node] : allSignals) {
    if ((node->type == NODE_OTHERS || node->type == NODE_READER || node->type == NODE_WRITER || node->type == NODE_READWRITER ||
        node->type == NODE_SPECIAL || node->type == NODE_EXT || node->type == NODE_EXT_IN || node->type == NODE_OUT)
        && node->super->prev.empty()) {
          g->supersrc.push_back(node->super);
        }
    Assert(!node->isArray(), "Array node is not supported in JSON mode");
  }
#ifdef ORDERED_TOPO_SORT
  std::sort(g->supersrc.begin(), g->supersrc.end(), [](SuperNode* a, SuperNode* b) {return a->id < b->id;});
#endif
  return g;
}
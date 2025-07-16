/**
 * @file PNode.cpp
 * @brief PNode class functions implementions
 */

#include <cstdarg>
#include "common.h"

void PNode::appendChild(std::unique_ptr<PNode> p) {
  if (p) child.push_back(std::move(p));
}
void PNode::appendExtraInfo(const std::string& info) { extraInfo.push_back(info); }
void PNode::appendChildList(std::unique_ptr<PList> &plist) {
  if (plist) child.insert(child.end(),
    std::make_move_iterator(plist->siblings.begin()), std::make_move_iterator(plist->siblings.end()));

  // todo: std::make_move_iterator and clear?
}
void PNode::setWidth(int _width) { width = _width; }

int PNode::getChildNum() { return child.size(); }

PNode* PNode::getChild(int idx) {
  Assert(idx < (int)child.size(), "idx %d is outof bound(%ld)", idx, child.size());
  return child[idx].get();
}
/*
void pnewNode(PNode* parent, int num, va_list valist) {
  for (int i = 0; i < num; i++) {
    auto next = std::move(va_arg(valist, std::unique_ptr<PNode>));
    parent->child.push_back(next);
  }
}*/


/*
std::unique_ptr<PNode> newNode(PNodeType type, int lineno, const char* info, const char* name, int num, ...) {
  auto parent = std::make_unique<PNode>(type, lineno);
  if (info) parent->info = std::string(info);
  if (name) parent->name = std::string(name);
  va_list valist;
  va_start(valist, num);
  pnewNode(parent.get(), num, valist);
  va_end(valist);
  return parent;
}

std::unique_ptr<PNode> newNode(PNodeType type, int lineno, const char* name, int num, ...) {
  auto parent = std::make_unique<PNode>(type, lineno);
  if (name) parent->name = std::string(name);
  va_list valist;
  va_start(valist, num);
  pnewNode(parent.get(), num, valist);
  va_end(valist);
  return parent;
}

std::unique_ptr<PNode> newNode(PNodeType type, int lineno, const char* info, const char* name) {
  auto parent = std::make_unique<PNode>(type, lineno);
  if (info) parent->info = std::string(info);
  if (name) parent->name = std::string(name);
  return parent;
}
*/
std::unique_ptr<PNode> newNode(PNodeType type, int lineno) {
  auto parent = std::make_unique<PNode>(type, lineno);
  return parent;
}

void PList::append(std::unique_ptr<PNode> pnode) {
  if (pnode) siblings.push_back(std::move(pnode));
}
/*
void PList::append(int num, ...) {
  va_list valist;
  va_start(valist, num);
  for (int i = 0; i < num; i++) {
    auto pnode = std::move(va_arg(valist, std::unique_ptr<PNode>));
    if (pnode) siblings.push_back(pnode);
  }
  va_end(valist);
}*/

void PList::concat(std::unique_ptr<PList> plist) {
  if (!plist) return;
  siblings.insert(siblings.end(),
    std::make_move_iterator(plist->siblings.begin()),
    std::make_move_iterator(plist->siblings.end()));
  plist->siblings.clear(); // optional??
}

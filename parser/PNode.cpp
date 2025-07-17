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
void PNode::appendChildList(std::unique_ptr<PList> plist) {
  if (plist) child.insert(child.end(),
    std::make_move_iterator(plist->siblings.begin()), std::make_move_iterator(plist->siblings.end()));
}
void PNode::setWidth(int _width) { width = _width; }

int PNode::getChildNum() { return child.size(); }

PNode* PNode::getChild(int idx) {
  Assert(idx < (int)child.size(), "idx %d is outof bound(%ld)", idx, child.size());
  return child[idx].get();
}

void PList::append(std::unique_ptr<PNode> pnode) {
  if (pnode) siblings.push_back(std::move(pnode));
}

void PList::concat(std::unique_ptr<PList> plist) {
  if (!plist) return;
  siblings.insert(siblings.end(),
    std::make_move_iterator(plist->siblings.begin()),
    std::make_move_iterator(plist->siblings.end()));
  plist->siblings.clear(); // optional??
}

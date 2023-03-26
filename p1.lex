%{
//----------------------------------------------------------------------------------
//  ECE 466 Project 1 - The Matrix
//  
//  Description: This project implements a C-like language that supports floating
//  point calculations and basic 2x2 matrix operations.
//
//  This file contains the scanner.
//
//  Joseph Homenick
//  February 2023
//
//----------------------------------------------------------------------------------

#include <stdio.h>
#include <math.h>
#include <cstdio>
#include <list>
#include <iostream>
#include <string>
#include <memory>
#include <stdexcept>

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Value.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/IRBuilder.h"

#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/Support/SystemUtils.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/FileSystem.h"

using namespace std;
using namespace llvm;

struct Expression
{
    vector <Value *>  * m;
    Value * v;
    bool isMatrix;
};

#include "p1.y.hpp"


%}

  //%option debug

%%

[ \t \n \r]         //ignore whitespace, tab, newline, and carriage return

return       { return RETURN; }
det          { return DET; }
transpose    { return TRANSPOSE; }
invert       { return INVERT; }
matrix       { return MATRIX; }
reduce       { return REDUCE; }
x            { return X; }

[a-zA-Z_][a-zA-Z_0-9]* { yylval.str = strdup (yytext); return ID; } //duplicate string

[0-9]+        { yylval.i = atoi(yytext); return INT; } //convert string to int

[0-9]+("."[0-9]*) { yylval.f = atof(yytext); return FLOAT; } //convert string to float

"["           { return LBRACKET; }
"]"           { return RBRACKET; }
"{"           { return LBRACE; }
"}"           { return RBRACE; }
"("           { return LPAREN; }
")"           { return RPAREN; }

"="           { return ASSIGN; }
"*"           { return MUL; }
"/"           { return DIV; }
"+"           { return PLUS; }
"-"           { return MINUS; }

","           { return COMMA; }

";"           { return SEMI; }


"//".*\n      {} //comment in source code

.             {return ERROR;}
%%

int yywrap()
{
  return 1;
}

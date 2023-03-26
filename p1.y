//----------------------------------------------------------------------------------
//  ECE 466 Project 1 - The Matrix
//  
//  Description: This project implements a C-like language that supports floating
//  point calculations and basic 2x2 matrix operations.
//
//  This file contains the parser.
//
//  Joseph Homenick
//  February 2023
//
//-----------------------------------------------------------------------------------

%{
#include <cstdio>
#include <list>
#include <vector>
#include <map>
#include <iostream>
#include <fstream>
#include <string>
#include <memory>
#include <stdexcept>

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Value.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Verifier.h"

#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/Support/SystemUtils.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/Support/FileSystem.h"

using namespace llvm;
using namespace std;

// Need for parser and scanner
extern FILE *yyin;
int yylex();
void yyerror(const char*);
int yyparse();
 
// Needed for LLVM
string funName;
Module *M;
LLVMContext TheContext;
IRBuilder<> Builder(TheContext);


//Create map for associating floating point values to an ID
map <string, Value *> ID_map;

//Create vector for parameter list
vector <string> ID_vect;

//Create map for associating matrices to an ID
//Represent 2x2 matrix with vector
map <string, vector <Value *> * > ID_map_matrix;

//Create vector to hold expr_list;
vector <Value * > expr_vect;

//Create map to associate an ID with an int to detertmine 
//if the expression associated with the ID is a matrix or not
//1 = is a matrix, 0 = is not a matrix
map <string, int> isM;


//Create a struct to select between float (Value *) and matrix ( vector <Value *> * )
//
//  Represent a matrix with a vector<Value *>
//
//  For a matrix [2 x 2]  { [a, b], [c, d] } represented by a vector <Value *> v:
//  a = v[0], b = v[1], c = v[2], d = v[3]
//
//  **NOTE: ONLY 2 x 2 MATRICES ARE SUPPORTED**
//

struct Expression
{
    vector <Value *> * m; //matrix
    Value * v; //float value
    bool isMatrix; //boolean to determine if expr is a float or matrix
};

%}

%union
{
  int i;
  float f;
  char * str;
  Value * val;
  struct Expression e;
}

%define parse.trace

%token ERROR
%token RETURN
%token DET
%token TRANSPOSE INVERT
%token REDUCE
%token MATRIX
%token X
%token <f> FLOAT
%token <i> INT
%token <str> ID
%token SEMI COMMA
%token PLUS MINUS MUL DIV
%token ASSIGN
%token LBRACKET RBRACKET
%token LPAREN RPAREN 
%token LBRACE RBRACE
%type <str> params_list
%type <e> expr
%type <val> matrix_rows
%type <val> matrix_row expr_list
%type  dim
%left PLUS MINUS
%left MUL DIV 

%start program

%%

program: ID
{
  funName = $1; //program name is string 'ID'
}
LPAREN params_list_opt RPAREN LBRACE statements_opt return RBRACE
{
  // parsing is done, input is accepted
  YYACCEPT;
}
;

params_list_opt:  params_list 
{
  std::vector<Type*> param_types(ID_vect.size(),Builder.getFloatTy());

  ArrayRef<Type*> Params (param_types);
  
  // Create int function type with no arguments
  FunctionType *FunType = 
    FunctionType::get(Builder.getFloatTy(),Params,false);

  // Create a main function
  Function *Function = Function::Create(FunType,GlobalValue::ExternalLinkage,funName,M);

  int arg_no=0;
  for(auto &a: Function->args())
  {
    // match arguments to name in parameter list, iterating over arguments of function
    Value * val = &a;  // refers to arg_no argument

    // map val to the ID at position arg_no
    ID_map[ID_vect[arg_no]] = val;

    arg_no++;
  }
  
  //Add a basic block to main to hold instructions, and set Builder
  //to insert there
  Builder.SetInsertPoint(BasicBlock::Create(TheContext, "entry", Function));
}
| %empty
{ 
  // Create int function type with no arguments
  FunctionType *FunType = 
    FunctionType::get(Builder.getFloatTy(),false);

  // Create a main function
  Function *Function = Function::Create(FunType,  
         GlobalValue::ExternalLinkage,funName,M);

  //Add a basic block to main to hold instructions, and set Builder
  //to insert there
  Builder.SetInsertPoint(BasicBlock::Create(TheContext, "entry", Function));
}
;

params_list: ID
{
    ID_vect.push_back($1);
    //Append ID to params_list
}
| params_list COMMA ID
{
    ID_vect.push_back($3);
    //Append ID to params_list
}
;

return: RETURN expr SEMI
{
  if ((!$2.isMatrix) && ($2.v != NULL)) //only return DEFINED FLOAT values
  {
    Builder.CreateRet($2.v);
    //return expr, ONLY FLOATS
  }
  
  else
  {
    cout << "Error!" << endl;
    YYABORT;
  }
  
}
;

statements_opt: %empty
            | statements
//NOTHING TO DO HERE
;

statements:   statement
            | statements statement
//NOTHING TO DO HERE
;

statement: ID ASSIGN expr SEMI
{
        if (!$3.isMatrix) //assign ID to a float value
        {
        ID_map[$1] = $3.v;
        isM[$1] = 0; //ID is not associated with a matrix
        }
        else //assigning a matrix to another matrix 
        {
           vector <Value *> * vals = new vector<Value *>; //create new pointer to a vector <Value *> to hold matrix
           vals->insert(vals->begin(), $3.m->begin(), $3.m->end()); //copy values to new matrix vector
           ID_map_matrix[$1] = vals; //assign ID to new matrix vector pointer
           isM[$1] = 1; //ID is associated with a matrix
        }

}
| ID ASSIGN MATRIX dim LBRACE matrix_rows RBRACE SEMI
{
    //Create a new matrix and assign to an ID

    vector <Value *> * vals = new vector <Value *>; //create new pointer to a vector <Value *> to hold matrix
    vals->insert(vals->begin(), expr_vect.begin(), expr_vect.end()); //copy values from expr_list (matrix row values) to matrix vector
    ID_map_matrix[$1] = vals; //associate ID with matrix vector pointer
    expr_vect.clear(); //clear expr_list so old values will not be used if another matrix is created
    isM[$1] = 1; //ID is associated with a matrix
}
;

dim: LBRACKET INT X INT RBRACKET
{
   //466 MATRICES ARE ALWAYS 2 X 2
   //NOTHING TO DO HERE

}
;

matrix_rows: matrix_row
{
    //NOTHING TO DO HERE
}
| matrix_rows COMMA matrix_row
{
    //NOTHING TO DO HERE
}
;

matrix_row: LBRACKET expr_list RBRACKET
{
    //NOTHING TO DO HERE
}
;

expr_list: expr //expr_list is the list of values for the matrix elements
{
    expr_vect.push_back($1.v); //append expr (float value) to expr_list
}
| expr_list COMMA expr
{
    expr_vect.push_back($3.v); //append expr (float value) to expr_list
}
;

expr: ID
{
    if(isM[$1]) //ID is associated with a matrix
    {
        $$.m = ID_map_matrix[$1];
        $$.isMatrix = true;
    }
    else //ID is associated with a float value
    {
        $$.v = ID_map[$1];
        $$.isMatrix = false;
    }


}
| FLOAT
{
    $$.isMatrix = false;
    $$.v = ConstantFP::get(Builder.getFloatTy(), APFloat($1));
    //expr = float value 'FLOAT'
}
| INT
{
    $$.isMatrix = false;
    $$.v = Builder.CreateUIToFP(Builder.getInt32($1), Builder.getFloatTy());
    //create unsigned int value from value 'INT', then convert to float
}
| expr PLUS expr
{
    if (( $1.isMatrix && !$3.isMatrix) || (!$1.isMatrix && $3.isMatrix))
    {
      cout << "Error!" << endl; //can't add floats and matrices, and vice versa
      YYABORT;
    }

    if ($1.isMatrix && $3.isMatrix) //matrix + matrix
    {
        $$.isMatrix = true;
        vector <Value *>  * tmp1 = $1.m;
        vector <Value *>& v1 = *tmp1; //first matrix
        vector <Value *>  * tmp2 = $3.m;
        vector <Value *>& v2 = *tmp2; //second matrix
        vector <Value *> * m_addition = new vector <Value *>; //create new vector to return result of addition of two vectors
        Value * num;
        
        // For a matrix [2 x 2]  { [a, b], [c, d] } m1 and a matrix [2 x 2]  { [e, f], [g, h] } m2:
        // m1 + m2 = matrix [2 x 2]  { [a+e, b+f], [c+g, d+h] }

        num = Builder.CreateFAdd(v1[0], v2[0], "add"); //a + e
        m_addition->push_back(num);
        num = Builder.CreateFAdd(v1[1], v2[1], "add"); //b + f
        m_addition->push_back(num);
        num = Builder.CreateFAdd(v1[2], v2[2], "add"); //c + g
        m_addition->push_back(num);
        num = Builder.CreateFAdd(v1[3], v2[3], "add"); //d + h
        m_addition->push_back(num);
        $$.m = m_addition;
    }
    else //float + float
    {
        $$.isMatrix = false;
        $$.v = Builder.CreateFAdd($1.v, $3.v, "add");
        //expr = floating point addition of expr $1 and expr $3
    }
}

| expr MINUS expr
{
    if (( $1.isMatrix && !$3.isMatrix) || (!$1.isMatrix && $3.isMatrix))
    {
      cout << "Error!" << endl; //can't subtract floats and matrices, and vice versa
      YYABORT;
    }

    if ($1.isMatrix && $3.isMatrix) //matrix - matrix
    {
        // For a matrix [2 x 2]  { [a, b], [c, d] } m1 and a matrix [2 x 2]  { [e, f], [g, h] } m2:
        // m1 - m2 = matrix [2 x 2]  { [a-e, b-f], [c-g, d-h] }

        $$.isMatrix = true;
        vector <Value *>  * tmp1 = $1.m;
        vector <Value *>& v1 = *tmp1; //first matrix
        vector <Value *>  * tmp2 = $3.m;
        vector <Value *>& v2 = *tmp2; //second matrix
        vector <Value *> * m_subtraction = new vector <Value *>; //create new vector to return result of subtraction of two vectors
        Value * num;

        num = Builder.CreateFSub(v1[0], v2[0], "sub"); //a - e
        m_subtraction->push_back(num);
        num = Builder.CreateFSub(v1[1], v2[1], "sub"); //b - f
        m_subtraction->push_back(num);
        num = Builder.CreateFSub(v1[2], v2[2], "sub"); //c - g
        m_subtraction->push_back(num);
        num = Builder.CreateFSub(v1[3], v2[3], "sub"); //g - h 
        m_subtraction->push_back(num);
        $$.m = m_subtraction;

    }
    else //float - float
    {
        $$.isMatrix = false;
        $$.v = Builder.CreateFSub($1.v, $3.v, "sub");
        //expr = floating point subtraction of expr $1 and expr $3
    }

}
| expr MUL expr
{
    
    if ($1.isMatrix && $3.isMatrix) //matrix * matrix
    {
        // For a matrix [2 x 2]  { [a, b], [c, d] } m1 and a matrix [2 x 2]  { [e, f], [g, h] } m2:
        // m1 * m2 = matrix [2 x 2]  { [ae + bg, af + bh], [ce + dg, cf + dh] }

        $$.isMatrix = true;
        vector <Value *>  * tmp1 = $1.m;
        vector <Value *>& v1 = *tmp1; //first matrix
        vector <Value *>  * tmp2 = $3.m;
        vector <Value *>& v2 = *tmp2; //second matrix
        vector <Value *> * m_mul = new vector <Value *>; //create new vector pointer for result of multiplication of two matrices
        Value * num1; //temp variable for intermediate calculations
        Value * num2; //temp variable for intermediate calculations
        Value * num3; //temp variable for intermediate calculations

        num1 = Builder.CreateFMul(v1[0], v2[0], "mul"); //a * e
        num2 = Builder.CreateFMul(v1[1], v2[2], "mul"); //b * g
        num3 = Builder.CreateFAdd(num1, num2, "add"); //ae + bg
        m_mul->push_back(num3);
        num1 = Builder.CreateFMul(v1[0], v2[1], "mul"); //a * f
        num2 = Builder.CreateFMul(v1[1], v2[3], "mul"); //b * h
        num3 = Builder.CreateFAdd(num1, num2, "add"); //af + bh
        m_mul->push_back(num3);
        num1 = Builder.CreateFMul(v1[2], v2[0], "mul"); //c * e
        num2 = Builder.CreateFMul(v1[3], v2[2], "mul"); //d * g
        num3 = Builder.CreateFAdd(num1, num2, "add"); //ce + dg
        m_mul->push_back(num3);
        num1 = Builder.CreateFMul(v1[2], v2[1], "mul"); //c * f
        num2 = Builder.CreateFMul(v1[3], v2[3], "mul"); //d * h
        num3 = Builder.CreateFAdd(num1, num2, "add"); //cf + dh
        m_mul->push_back(num3);
        $$.m = m_mul;
    }
    else //float * float
    {
        $$.isMatrix = false;
        $$.v = Builder.CreateFMul($1.v, $3.v, "mul");
        //expr = floating point multiplication of expr $1 and expr $3
    }
    //466 DOES NOT NEED TO SUPPORT MULTIPLICATION OF MATRIX BY CONSTANT

}
| expr DIV expr
{

    $$.isMatrix = false;
    $$.v = Builder.CreateFDiv($1.v, $3.v, "div");
    //expr = floating point division of expr $1 and expr $3

    //466 DOES NOT NEED TO SUPPORT DIVISION OF MATRIX BY CONSTANT
    //466 DOES NOT NEED TO SUPPORT MATRIX DIVISION SINCE INVERT DOES NOT NEED TO BE SUPPORTED
}
| MINUS expr
{
    if ($2.isMatrix) //negate matrix
    {
        // For a matrix [2 x 2]  { [a, b], [c, d] } m :
        // -m = matrix [2 x 2]  { [-a, -b], [-c, -d] }

        $$.isMatrix = true;
        vector <Value *>  * tmp1 = $2.m;
        vector <Value *>& v = *tmp1; //matrix
        vector <Value *> * m_negate = new vector <Value *>; //create new vector pointer to return result of matrix negation
        Value * num;

        num = Builder.CreateFNeg(v[0], "neg"); //-a
        m_negate->push_back(num);
        num = Builder.CreateFNeg(v[1], "neg"); //-b
        m_negate->push_back(num);
        num = Builder.CreateFNeg(v[2], "neg"); //-c
        m_negate->push_back(num);
        num = Builder.CreateFNeg(v[3], "neg"); //-d
        m_negate->push_back(num);
        $$.m = m_negate;

    }
    else //negate a float
    {
        $$.isMatrix = false;
        $$.v = Builder.CreateFNeg($2.v, "neg");
        //expr = floating point negation of expr $1
    }
}
| DET LPAREN expr RPAREN
{
  if ((!$3.isMatrix))
    {
      cout << "Error!" << endl; //can't take determinant of float
      YYABORT;
    }

    //Determinant of 2 x 2 matrix m { [a,b], [c,d] }: DET(m) = a*d - b*c

    vector <Value *>  * tmp = $3.m;
    vector <Value *>& v = *tmp;

    Value * tmp1;
    Value * tmp2;

    tmp1 = Builder.CreateFMul(v[0],v[3], "mul"); //a*d
    tmp2 = Builder.CreateFMul(v[1],v[2], "mul"); //b*c
    $$.v = Builder.CreateFSub(tmp1, tmp2, "sub"); //a*d - b*c
    $$.isMatrix = false;

}
| INVERT LPAREN expr RPAREN
{
    //466 DOES NOT HAVE TO IMPLEMENT
}
| TRANSPOSE LPAREN expr RPAREN
{
    //466 DOES NOT HAVE TO IMPLEMENT
}
| ID LBRACKET INT COMMA INT RBRACKET //get element at [ROW, COLUMN]
{

    vector <Value *>  * tmp = ID_map_matrix[$1];
    vector <Value *>& v = *tmp; //get vector matrix associated with ID

    if ( ( $3 == 0) && ($5 == 0) ) //get element at ROW 0, COLUMN 0
    {
        $$.isMatrix = false;
        $$.v = v[0];
    }

    if ( ( $3 == 0) && ($5 == 1) ) //get element at ROW 0, COLUMN 1
    {
        $$.isMatrix = false;
        $$.v = v[2];
    }

    if ( ( $3 == 1) && ($5 == 0) ) //get element at ROW 1, COLUMN 0
    {
        $$.isMatrix = false;
        $$.v = v[2];
    }

    if ( ( $3 == 1) && ($5 == 1) ) //get element at ROW 1, COLUMN 1
    {
        $$.isMatrix = false;
        $$.v = v[3];
    }
}
| REDUCE LPAREN expr RPAREN
{
  if ((!$3.isMatrix))
    {
      cout << "Error!" << endl; //can't reduce float
      YYABORT;
    }

    //Sum all elements of matrix [2 x 2] { [a,b], [c,d] } m : REDUCE(m) = a + b + c + d

    vector <Value *>  * tmp = $3.m;
    vector <Value *>& v = *tmp;
    Value * tmp1;

    tmp1 = Builder.CreateFAdd(v[0], v[1], "add"); //a + b
    tmp1 = Builder.CreateFAdd(tmp1, v[2], "add"); //a + b + c
    tmp1 = Builder.CreateFAdd(tmp1, v[3], "add"); //a + b + c + d
    $$.v = tmp1;
    $$.isMatrix = false;
}
| LPAREN expr RPAREN
{
    $$ = $2;

}
;


%%

unique_ptr<Module> parseP1File(const string &InputFilename)
{
  string modName = InputFilename;
  if (modName.find_last_of('/') != string::npos)
    modName = modName.substr(modName.find_last_of('/')+1);
  if (modName.find_last_of('.') != string::npos)
    modName.resize(modName.find_last_of('.'));

  // unique_ptr will clean up after us, call destructor, etc.
  unique_ptr<Module> Mptr(new Module(modName.c_str(), TheContext));

  // set global module
  M = Mptr.get();
  
  /* this is the name of the file to generate, you can also use
     this string to figure out the name of the generated function */

  if (InputFilename == "--")
    yyin = stdin;
  else	  
    yyin = fopen(InputFilename.c_str(),"r");

  //yydebug = 1;
  if (yyparse() != 0) {
    // Dump LLVM IR to the screen for debugging
    M->print(errs(),nullptr,false,true);
    // errors, so discard module
    Mptr.reset();
  } else {
    // Dump LLVM IR to the screen for debugging
    M->print(errs(),nullptr,false,true);
  }
  
  return Mptr;
}

void yyerror(const char* msg)
{
  printf("%s\n",msg);
}

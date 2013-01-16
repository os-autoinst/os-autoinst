%module tinycv

%include "std_vector.i"
%include "std_string.i"

namespace std {
        %template(vectorc) vector<char>;
        %template(vectori) vector<int>;
}

%{
        #include "tinycv.h"
%}


%include "tinycv.h"

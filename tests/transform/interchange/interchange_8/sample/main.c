float A[100][100];

void foo() {

  for (int I = 0; I < 100; ++I)
    for (int J = 1; J < 100; ++J)
      A[I][J] = A[I][J - 1];
}

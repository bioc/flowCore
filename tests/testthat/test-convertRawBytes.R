context("converting raw vector to integer or numeric that has different bitwidths")
origVec <- c(1:10)
origVec_num <- as.numeric(c(1:10))

test_that("raw to int", {
  # Integer
  
  nPar <- 5
  nByteSize <- 4
  size <- rep(nByteSize, nPar)
  rawVec <- writeBin(origVec, raw(), size = nByteSize, endian = "little")
  # wrong size vec
  expect_error(convertRawBytes(rawVec, isInt = T, colSize = 4L, ncol = as.integer(nPar), isBigEndian = F), "length of 'colSize'", class = "error")
  
  expect_identical(origVec_num, convertRawBytes(rawVec, isInt = T, colSize = as.integer(size), ncol = as.integer(nPar), isBigEndian = F))
  
  #byte size other than 4
  nByteSize <- 2
  size <- rep(nByteSize, nPar)
  rawVec <- writeBin(origVec, raw(), size = nByteSize, endian = "little")
  expect_identical(origVec_num, convertRawBytes(rawVec, isInt = T, colSize = as.integer(size), ncol = as.integer(nPar), isBigEndian = F))
  
  nByteSize <- 1
  size <- rep(nByteSize, nPar)
  origVec1 <- origVec
  origVec1[1] <- 255L #test max uint8
  rawVec <- writeBin(origVec1, raw(), size = nByteSize, endian = "little")
  expect_identical(as.numeric(origVec1), convertRawBytes(rawVec, isInt = T, colSize = as.integer(size), ncol = as.integer(nPar), isBigEndian = F))
  
      
  
  #big endian
  rawVec <- writeBin(origVec, raw(), size = nByteSize, endian = "big")
  expect_identical(origVec_num, convertRawBytes(rawVec, isInt = T, colSize = as.integer(size), ncol = as.integer(nPar), isBigEndian = T))
  
  #mixed sizes
  size <- c(2,2,2,4,4)
  rawVec1 <- writeBin(origVec[c(1:3,6:8)], raw(), size = 2, endian = "little")
  rawVec2 <- writeBin(origVec[c(4:5,9:10)], raw(), size = 4, endian = "little")
  rawVec <- c(rawVec1[1:6], rawVec2[1:8], rawVec1[7:12], rawVec2[9:16])
  expect_identical(origVec_num, convertRawBytes(rawVec, isInt = T, colSize = as.integer(size), ncol = as.integer(nPar), isBigEndian = F))
  
  
})

test_that("raw to numeric", {
  # double
  
  nPar <- 5
  nByteSize <- 8
  size <- rep(nByteSize, nPar)
  rawVec <- writeBin(origVec_num, raw(), size = nByteSize, endian = "little")
  expect_identical(origVec_num,convertRawBytes(rawVec, isInt = F, colSize = as.integer(size), ncol = as.integer(nPar), isBigEndian = F))
  
  #big endian
  rawVec <- writeBin(origVec_num, raw(), size = nByteSize, endian = "big")
  expect_identical(origVec_num,convertRawBytes(rawVec, isInt = F, colSize = as.integer(size), ncol = as.integer(nPar), isBigEndian = T))
  
  nByteSize <- 4
  size <- rep(nByteSize, nPar)
  rawVec <- writeBin(origVec_num, raw(), size = nByteSize, endian = "little")
  expect_identical(origVec_num,convertRawBytes(rawVec, isInt = F, colSize = as.integer(size), ncol = as.integer(nPar), isBigEndian = F))
  
  
  
})

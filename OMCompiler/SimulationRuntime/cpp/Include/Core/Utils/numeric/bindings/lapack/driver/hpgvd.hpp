//
// Copyright (c) 2002--2010
// Toon Knapen, Karl Meerbergen, Kresimir Fresl,
// Thomas Klimpel and Rutger ter Borg
//
// Distributed under the Boost Software License, Version 1.0.
// (See accompanying file LICENSE_1_0.txt or copy at
// http://www.boost.org/LICENSE_1_0.txt)
//
// THIS FILE IS AUTOMATICALLY GENERATED
// PLEASE DO NOT EDIT!
//

#ifndef BOOST_NUMERIC_BINDINGS_LAPACK_DRIVER_HPGVD_HPP
#define BOOST_NUMERIC_BINDINGS_LAPACK_DRIVER_HPGVD_HPP

#include <boost/assert.hpp>
#include <Core/Utils/numeric/bindings/begin.hpp>
#include <Core/Utils/numeric/bindings/detail/array.hpp>
#include <Core/Utils/numeric/bindings/is_column_major.hpp>
#include <Core/Utils/numeric/bindings/is_complex.hpp>
#include <Core/Utils/numeric/bindings/is_mutable.hpp>
#include <Core/Utils/numeric/bindings/is_real.hpp>
#include <Core/Utils/numeric/bindings/lapack/workspace.hpp>
#include <Core/Utils/numeric/bindings/remove_imaginary.hpp>
#include <Core/Utils/numeric/bindings/size.hpp>
#include <Core/Utils/numeric/bindings/stride.hpp>
#include <Core/Utils/numeric/bindings/traits/detail/utils.hpp>
#include <Core/Utils/numeric/bindings/uplo_tag.hpp>
#include <Core/Utils/numeric/bindings/value_type.hpp>
#include <boost/static_assert.hpp>
#include <boost/type_traits/is_same.hpp>
#include <boost/type_traits/remove_const.hpp>
#include <boost/utility/enable_if.hpp>

//
// The LAPACK-backend for hpgvd is the netlib-compatible backend.
//
#include <Core/Utils/numeric/bindings/lapack/detail/lapack.h>
#include <Core/Utils/numeric/bindings/lapack/detail/lapack_option.hpp>

namespace boost {
namespace numeric {
namespace bindings {
namespace lapack {

//
// The detail namespace contains value-type-overloaded functions that
// dispatch to the appropriate back-end LAPACK-routine.
//
namespace detail {

//
// Overloaded function for dispatching to
// * netlib-compatible LAPACK backend (the default), and
// * float value-type.
//
template< typename UpLo >
inline std::ptrdiff_t hpgvd( const fortran_int_t itype, const char jobz,
        const UpLo, const fortran_int_t n, float* ap, float* bp, float* w,
        float* z, const fortran_int_t ldz, float* work,
        const fortran_int_t lwork, fortran_int_t* iwork,
        const fortran_int_t liwork ) {
    fortran_int_t info(0);
    LAPACK_SSPGVD( &itype, &jobz, &lapack_option< UpLo >::value, &n, ap, bp,
            w, z, &ldz, work, &lwork, iwork, &liwork, &info );
    return info;
}

//
// Overloaded function for dispatching to
// * netlib-compatible LAPACK backend (the default), and
// * double value-type.
//
template< typename UpLo >
inline std::ptrdiff_t hpgvd( const fortran_int_t itype, const char jobz,
        const UpLo, const fortran_int_t n, double* ap, double* bp, double* w,
        double* z, const fortran_int_t ldz, double* work,
        const fortran_int_t lwork, fortran_int_t* iwork,
        const fortran_int_t liwork ) {
    fortran_int_t info(0);
    LAPACK_DSPGVD( &itype, &jobz, &lapack_option< UpLo >::value, &n, ap, bp,
            w, z, &ldz, work, &lwork, iwork, &liwork, &info );
    return info;
}

//
// Overloaded function for dispatching to
// * netlib-compatible LAPACK backend (the default), and
// * complex<float> value-type.
//
template< typename UpLo >
inline std::ptrdiff_t hpgvd( const fortran_int_t itype, const char jobz,
        const UpLo, const fortran_int_t n, std::complex<float>* ap,
        std::complex<float>* bp, float* w, std::complex<float>* z,
        const fortran_int_t ldz, std::complex<float>* work,
        const fortran_int_t lwork, float* rwork, const fortran_int_t lrwork,
        fortran_int_t* iwork, const fortran_int_t liwork ) {
    fortran_int_t info(0);
    LAPACK_CHPGVD( &itype, &jobz, &lapack_option< UpLo >::value, &n, ap, bp,
            w, z, &ldz, work, &lwork, rwork, &lrwork, iwork, &liwork, &info );
    return info;
}

//
// Overloaded function for dispatching to
// * netlib-compatible LAPACK backend (the default), and
// * complex<double> value-type.
//
template< typename UpLo >
inline std::ptrdiff_t hpgvd( const fortran_int_t itype, const char jobz,
        const UpLo, const fortran_int_t n, std::complex<double>* ap,
        std::complex<double>* bp, double* w, std::complex<double>* z,
        const fortran_int_t ldz, std::complex<double>* work,
        const fortran_int_t lwork, double* rwork, const fortran_int_t lrwork,
        fortran_int_t* iwork, const fortran_int_t liwork ) {
    fortran_int_t info(0);
    LAPACK_ZHPGVD( &itype, &jobz, &lapack_option< UpLo >::value, &n, ap, bp,
            w, z, &ldz, work, &lwork, rwork, &lrwork, iwork, &liwork, &info );
    return info;
}

} // namespace detail

//
// Value-type based template class. Use this class if you need a type
// for dispatching to hpgvd.
//
template< typename Value, typename Enable = void >
struct hpgvd_impl {};

//
// This implementation is enabled if Value is a real type.
//
template< typename Value >
struct hpgvd_impl< Value, typename boost::enable_if< is_real< Value > >::type > {

    typedef Value value_type;
    typedef typename remove_imaginary< Value >::type real_type;

    //
    // Static member function for user-defined workspaces, that
    // * Deduces the required arguments for dispatching to LAPACK, and
    // * Asserts that most arguments make sense.
    //
    template< typename MatrixAP, typename MatrixBP, typename VectorW,
            typename MatrixZ, typename WORK, typename IWORK >
    static std::ptrdiff_t invoke( const fortran_int_t itype,
            const char jobz, MatrixAP& ap, MatrixBP& bp, VectorW& w,
            MatrixZ& z, detail::workspace2< WORK, IWORK > work ) {
        namespace bindings = ::boost::numeric::bindings;
        typedef typename result_of::uplo_tag< MatrixAP >::type uplo;
        BOOST_STATIC_ASSERT( (bindings::is_column_major< MatrixZ >::value) );
        BOOST_STATIC_ASSERT( (boost::is_same< typename remove_const<
                typename bindings::value_type< MatrixAP >::type >::type,
                typename remove_const< typename bindings::value_type<
                MatrixBP >::type >::type >::value) );
        BOOST_STATIC_ASSERT( (boost::is_same< typename remove_const<
                typename bindings::value_type< MatrixAP >::type >::type,
                typename remove_const< typename bindings::value_type<
                VectorW >::type >::type >::value) );
        BOOST_STATIC_ASSERT( (boost::is_same< typename remove_const<
                typename bindings::value_type< MatrixAP >::type >::type,
                typename remove_const< typename bindings::value_type<
                MatrixZ >::type >::type >::value) );
        BOOST_STATIC_ASSERT( (bindings::is_mutable< MatrixAP >::value) );
        BOOST_STATIC_ASSERT( (bindings::is_mutable< MatrixBP >::value) );
        BOOST_STATIC_ASSERT( (bindings::is_mutable< VectorW >::value) );
        BOOST_STATIC_ASSERT( (bindings::is_mutable< MatrixZ >::value) );
        BOOST_ASSERT( bindings::size(work.select(fortran_int_t())) >=
                min_size_iwork( jobz, bindings::size_column(ap) ));
        BOOST_ASSERT( bindings::size(work.select(real_type())) >=
                min_size_work( jobz, bindings::size_column(ap) ));
        BOOST_ASSERT( bindings::size_column(ap) >= 0 );
        BOOST_ASSERT( bindings::size_minor(z) == 1 ||
                bindings::stride_minor(z) == 1 );
        BOOST_ASSERT( jobz == 'N' || jobz == 'V' );
        return detail::hpgvd( itype, jobz, uplo(), bindings::size_column(ap),
                bindings::begin_value(ap), bindings::begin_value(bp),
                bindings::begin_value(w), bindings::begin_value(z),
                bindings::stride_major(z),
                bindings::begin_value(work.select(real_type())),
                bindings::size(work.select(real_type())),
                bindings::begin_value(work.select(fortran_int_t())),
                bindings::size(work.select(fortran_int_t())) );
    }

    //
    // Static member function that
    // * Figures out the minimal workspace requirements, and passes
    //   the results to the user-defined workspace overload of the
    //   invoke static member function
    // * Enables the unblocked algorithm (BLAS level 2)
    //
    template< typename MatrixAP, typename MatrixBP, typename VectorW,
            typename MatrixZ >
    static std::ptrdiff_t invoke( const fortran_int_t itype,
            const char jobz, MatrixAP& ap, MatrixBP& bp, VectorW& w,
            MatrixZ& z, minimal_workspace ) {
        namespace bindings = ::boost::numeric::bindings;
        typedef typename result_of::uplo_tag< MatrixAP >::type uplo;
        bindings::detail::array< real_type > tmp_work( min_size_work( jobz,
                bindings::size_column(ap) ) );
        bindings::detail::array< fortran_int_t > tmp_iwork(
                min_size_iwork( jobz, bindings::size_column(ap) ) );
        return invoke( itype, jobz, ap, bp, w, z, workspace( tmp_work,
                tmp_iwork ) );
    }

    //
    // Static member function that
    // * Figures out the optimal workspace requirements, and passes
    //   the results to the user-defined workspace overload of the
    //   invoke static member
    // * Enables the blocked algorithm (BLAS level 3)
    //
    template< typename MatrixAP, typename MatrixBP, typename VectorW,
            typename MatrixZ >
    static std::ptrdiff_t invoke( const fortran_int_t itype,
            const char jobz, MatrixAP& ap, MatrixBP& bp, VectorW& w,
            MatrixZ& z, optimal_workspace ) {
        namespace bindings = ::boost::numeric::bindings;
        typedef typename result_of::uplo_tag< MatrixAP >::type uplo;
        real_type opt_size_work;
        fortran_int_t opt_size_iwork;
        detail::hpgvd( itype, jobz, uplo(), bindings::size_column(ap),
                bindings::begin_value(ap), bindings::begin_value(bp),
                bindings::begin_value(w), bindings::begin_value(z),
                bindings::stride_major(z), &opt_size_work, -1,
                &opt_size_iwork, -1 );
        bindings::detail::array< real_type > tmp_work(
                traits::detail::to_int( opt_size_work ) );
        bindings::detail::array< fortran_int_t > tmp_iwork(
                opt_size_iwork );
        return invoke( itype, jobz, ap, bp, w, z, workspace( tmp_work,
                tmp_iwork ) );
    }

    //
    // Static member function that returns the minimum size of
    // workspace-array work.
    //
    static std::ptrdiff_t min_size_work( const char jobz,
            const std::ptrdiff_t n ) {
        if ( n < 2 )
            return 1;
        else {
            if ( jobz == 'N' )
                return 2*n;
            else
                return 1 + 6*n + n*n;
        }
    }

    //
    // Static member function that returns the minimum size of
    // workspace-array iwork.
    //
    static std::ptrdiff_t min_size_iwork( const char jobz,
            const std::ptrdiff_t n ) {
        if ( jobz == 'N' || n < 2 )
            return 1;
        else
            return 3 + 5*n;
    }
};

//
// This implementation is enabled if Value is a complex type.
//
template< typename Value >
struct hpgvd_impl< Value, typename boost::enable_if< is_complex< Value > >::type > {

    typedef Value value_type;
    typedef typename remove_imaginary< Value >::type real_type;

    //
    // Static member function for user-defined workspaces, that
    // * Deduces the required arguments for dispatching to LAPACK, and
    // * Asserts that most arguments make sense.
    //
    template< typename MatrixAP, typename MatrixBP, typename VectorW,
            typename MatrixZ, typename WORK, typename RWORK, typename IWORK >
    static std::ptrdiff_t invoke( const fortran_int_t itype,
            const char jobz, MatrixAP& ap, MatrixBP& bp, VectorW& w,
            MatrixZ& z, detail::workspace3< WORK, RWORK, IWORK > work ) {
        namespace bindings = ::boost::numeric::bindings;
        typedef typename result_of::uplo_tag< MatrixAP >::type uplo;
        BOOST_STATIC_ASSERT( (bindings::is_column_major< MatrixZ >::value) );
        BOOST_STATIC_ASSERT( (boost::is_same< typename remove_const<
                typename bindings::value_type< MatrixAP >::type >::type,
                typename remove_const< typename bindings::value_type<
                MatrixBP >::type >::type >::value) );
        BOOST_STATIC_ASSERT( (boost::is_same< typename remove_const<
                typename bindings::value_type< MatrixAP >::type >::type,
                typename remove_const< typename bindings::value_type<
                MatrixZ >::type >::type >::value) );
        BOOST_STATIC_ASSERT( (bindings::is_mutable< MatrixAP >::value) );
        BOOST_STATIC_ASSERT( (bindings::is_mutable< MatrixBP >::value) );
        BOOST_STATIC_ASSERT( (bindings::is_mutable< VectorW >::value) );
        BOOST_STATIC_ASSERT( (bindings::is_mutable< MatrixZ >::value) );
        BOOST_ASSERT( bindings::size(work.select(fortran_int_t())) >=
                min_size_iwork( jobz, bindings::size_column(ap) ));
        BOOST_ASSERT( bindings::size(work.select(real_type())) >=
                min_size_rwork( jobz, bindings::size_column(ap) ));
        BOOST_ASSERT( bindings::size(work.select(value_type())) >=
                min_size_work( jobz, bindings::size_column(ap) ));
        BOOST_ASSERT( bindings::size_column(ap) >= 0 );
        BOOST_ASSERT( bindings::size_minor(z) == 1 ||
                bindings::stride_minor(z) == 1 );
        BOOST_ASSERT( jobz == 'N' || jobz == 'V' );
        return detail::hpgvd( itype, jobz, uplo(), bindings::size_column(ap),
                bindings::begin_value(ap), bindings::begin_value(bp),
                bindings::begin_value(w), bindings::begin_value(z),
                bindings::stride_major(z),
                bindings::begin_value(work.select(value_type())),
                bindings::size(work.select(value_type())),
                bindings::begin_value(work.select(real_type())),
                bindings::size(work.select(real_type())),
                bindings::begin_value(work.select(fortran_int_t())),
                bindings::size(work.select(fortran_int_t())) );
    }

    //
    // Static member function that
    // * Figures out the minimal workspace requirements, and passes
    //   the results to the user-defined workspace overload of the
    //   invoke static member function
    // * Enables the unblocked algorithm (BLAS level 2)
    //
    template< typename MatrixAP, typename MatrixBP, typename VectorW,
            typename MatrixZ >
    static std::ptrdiff_t invoke( const fortran_int_t itype,
            const char jobz, MatrixAP& ap, MatrixBP& bp, VectorW& w,
            MatrixZ& z, minimal_workspace ) {
        namespace bindings = ::boost::numeric::bindings;
        typedef typename result_of::uplo_tag< MatrixAP >::type uplo;
        bindings::detail::array< value_type > tmp_work( min_size_work( jobz,
                bindings::size_column(ap) ) );
        bindings::detail::array< real_type > tmp_rwork( min_size_rwork( jobz,
                bindings::size_column(ap) ) );
        bindings::detail::array< fortran_int_t > tmp_iwork(
                min_size_iwork( jobz, bindings::size_column(ap) ) );
        return invoke( itype, jobz, ap, bp, w, z, workspace( tmp_work,
                tmp_rwork, tmp_iwork ) );
    }

    //
    // Static member function that
    // * Figures out the optimal workspace requirements, and passes
    //   the results to the user-defined workspace overload of the
    //   invoke static member
    // * Enables the blocked algorithm (BLAS level 3)
    //
    template< typename MatrixAP, typename MatrixBP, typename VectorW,
            typename MatrixZ >
    static std::ptrdiff_t invoke( const fortran_int_t itype,
            const char jobz, MatrixAP& ap, MatrixBP& bp, VectorW& w,
            MatrixZ& z, optimal_workspace ) {
        namespace bindings = ::boost::numeric::bindings;
        typedef typename result_of::uplo_tag< MatrixAP >::type uplo;
        value_type opt_size_work;
        real_type opt_size_rwork;
        fortran_int_t opt_size_iwork;
        detail::hpgvd( itype, jobz, uplo(), bindings::size_column(ap),
                bindings::begin_value(ap), bindings::begin_value(bp),
                bindings::begin_value(w), bindings::begin_value(z),
                bindings::stride_major(z), &opt_size_work, -1,
                &opt_size_rwork, -1, &opt_size_iwork, -1 );
        bindings::detail::array< value_type > tmp_work(
                traits::detail::to_int( opt_size_work ) );
        bindings::detail::array< real_type > tmp_rwork(
                traits::detail::to_int( opt_size_rwork ) );
        bindings::detail::array< fortran_int_t > tmp_iwork(
                opt_size_iwork );
        return invoke( itype, jobz, ap, bp, w, z, workspace( tmp_work,
                tmp_rwork, tmp_iwork ) );
    }

    //
    // Static member function that returns the minimum size of
    // workspace-array work.
    //
    static std::ptrdiff_t min_size_work( const char jobz,
            const std::ptrdiff_t n ) {
        if ( n < 2 )
            return 1;
        else {
            if ( jobz == 'N' )
                return n;
            else
                return 2*n;
        }
    }

    //
    // Static member function that returns the minimum size of
    // workspace-array rwork.
    //
    static std::ptrdiff_t min_size_rwork( const char jobz,
            const std::ptrdiff_t n ) {
        if ( n < 2 )
            return 1;
        else {
            if ( jobz == 'N' )
                return n;
            else
                return 1 + 5*n + 2*n*n;
        }
    }

    //
    // Static member function that returns the minimum size of
    // workspace-array iwork.
    //
    static std::ptrdiff_t min_size_iwork( const char jobz,
            const std::ptrdiff_t n ) {
        if ( jobz == 'N' || n < 2 )
            return 1;
        else
            return 3 + 5*n;
    }
};


//
// Functions for direct use. These functions are overloaded for temporaries,
// so that wrapped types can still be passed and used for write-access. In
// addition, if applicable, they are overloaded for user-defined workspaces.
// Calls to these functions are passed to the hpgvd_impl classes. In the
// documentation, most overloads are collapsed to avoid a large number of
// prototypes which are very similar.
//

//
// Overloaded function for hpgvd. Its overload differs for
// * User-defined workspace
//
template< typename MatrixAP, typename MatrixBP, typename VectorW,
        typename MatrixZ, typename Workspace >
inline typename boost::enable_if< detail::is_workspace< Workspace >,
        std::ptrdiff_t >::type
hpgvd( const fortran_int_t itype, const char jobz, MatrixAP& ap,
        MatrixBP& bp, VectorW& w, MatrixZ& z, Workspace work ) {
    return hpgvd_impl< typename bindings::value_type<
            MatrixAP >::type >::invoke( itype, jobz, ap, bp, w, z, work );
}

//
// Overloaded function for hpgvd. Its overload differs for
// * Default workspace-type (optimal)
//
template< typename MatrixAP, typename MatrixBP, typename VectorW,
        typename MatrixZ >
inline typename boost::disable_if< detail::is_workspace< MatrixZ >,
        std::ptrdiff_t >::type
hpgvd( const fortran_int_t itype, const char jobz, MatrixAP& ap,
        MatrixBP& bp, VectorW& w, MatrixZ& z ) {
    return hpgvd_impl< typename bindings::value_type<
            MatrixAP >::type >::invoke( itype, jobz, ap, bp, w, z,
            optimal_workspace() );
}

} // namespace lapack
} // namespace bindings
} // namespace numeric
} // namespace boost

#endif

import { useCallback, useEffect, useState } from "react";
import web3ModalSetup from "./../helpers/web3ModalSetup";
import Web3 from "web3";
import getAbi from "../Abi";
import getAbiBusd from "./../Abi/busd";
import { CONTRACTADDR } from "../Abi";
/* eslint-disable no-unused-vars */
const web3Modal = web3ModalSetup();

const Interface = () => {
  const [Abi, setAbi] = useState();
  const [AbiBusd, setAbiBusd] = useState();
  const [allowance, setAllowance] = useState();
  const [web3, setWeb3] = useState();
  const [isConnected, setIsConnected] = useState(false);
  const [injectedProvider, setInjectedProvider] = useState();
  const [refetch, setRefetch] = useState(true);
  const [current, setCurrent] = useState(null);
  const [owner, setOwner] = useState("");
  const [connButtonText, setConnButtonText] = useState("CONNECT");
  const [auctionId, setAuctionId] = useState(null);
  const [initialPrice, setInitialPrice] = useState("");
  const [seller, setSeller] = useState("");
  const [itemUrl, setItemUrl] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [auctionState, setAuctionState] = useState(0);
  const [bidAmount, setBidAmount] = useState("");
  const [bids, setBids] = useState([]);
  const [balance, setBalance] = useState(0);

  const [pendingMessage, setPendingMessage] = useState('');


  const logoutOfWeb3Modal = async () => {
    await web3Modal.clearCachedProvider();
    if (
      injectedProvider &&
      injectedProvider.provider &&
      typeof injectedProvider.provider.disconnect == "function"
    ) {
      await injectedProvider.provider.disconnect();
    }
    setIsConnected(false);

    window.location.reload();
  };
  const loadWeb3Modal = useCallback(async () => {
    const provider = await web3Modal.connect();
    setInjectedProvider(new Web3(provider));
    const acc = provider.selectedAddress
      ? provider.selectedAddress
      : provider.accounts[0];

    const short = shortenAddr(acc);

    setWeb3(new Web3(provider));
    setAbi(await getAbi(new Web3(provider)));
    setAbiBusd(await getAbiBusd(new Web3(provider)));
    setCurrent(acc);
    setIsConnected(true);

    setConnButtonText(short);

    provider.on("chainChanged", (chainId) => {
      console.log(`chain changed to ${chainId}! updating providers`);
      setInjectedProvider(new Web3(provider));
    });

    provider.on("accountsChanged", () => {
      console.log(`account changed!`);
      setInjectedProvider(new Web3(provider));
    });

    // Subscribe to session disconnection
    provider.on("disconnect", (code, reason) => {
      console.log(code, reason);
      logoutOfWeb3Modal();
    });
    // eslint-disable-next-line
  }, [setInjectedProvider]);

  useEffect(() => {
    setInterval(() => {
      setRefetch((prevRefetch) => {
        return !prevRefetch;
      });
    }, 3000);
  }, []);

  useEffect(() => {
    if (web3Modal.cachedProvider) {
      loadWeb3Modal();
    }
    // eslint-disable-next-line
  }, []);

  useEffect(() => {
    const approvalallowance = async () => {
      if (isConnected && AbiBusd) {

        let _allowance = await AbiBusd.methods.allowance(current, CONTRACTADDR).call();
        setAllowance(_allowance);

      }
    };

    approvalallowance();

  }, [isConnected, refetch]);

  useEffect(() => {
    const refData = async () => {
      if (isConnected && web3) {
        const owner = await Abi.methods.owner().call();
        setOwner(owner);
        const _bids = await Abi.methods.getAllBids().call();
        setBids(_bids);
        const _balance = await AbiBusd.methods.balanceOf(current).call();
        setBalance(_balance)
        const _auctionState = await Abi.methods.auction_state().call();
        setAuctionState(_auctionState);
        if (auctionState == 1) {
          setPendingMessage("Auction started")
        } else if (auctionState == 2) {
          setPendingMessage("Auction finished")
        }
      }
    };

    refData();
  }, [isConnected, current, web3, refetch]);
  const shortenAddr = (addr) => {
    if (!addr) return "";
    const first = addr.substr(0, 3);
    const last = addr.substr(38, 41);
    return first + "..." + last;
  };

  const approval = async (e) => {
    e.preventDefault();
    if (isConnected && AbiBusd) {
      setPendingMessage("Approving Busd");
      let getAllowance = await AbiBusd.methods.allowance(current, CONTRACTADDR).call();
      console.log(getAllowance);
      let _amount = '100000000000000000000000000000000000';
      await AbiBusd.methods.approve(CONTRACTADDR, _amount).send({
        from: current,
      });
      setPendingMessage("Approved Successfully");
    }
    else {
      console.log("connect wallet");
    }
  };

  const createAuction = async (e) => {
    e.preventDefault();
    if (isConnected && Abi) {
      let startTime = (new Date(startDate).getTime() - Date.now()) / 1000;
      let endTime = (new Date(endDate).getTime() - Date.now()) / 1000;
      if (startTime < endTime) {

        let _initial_price = web3.utils.toWei(initialPrice);
        console.log(_initial_price)
        if (startTime < 0) startTime = 0;
        if (endTime < 0) endTime = 0;
        console.log(startTime, endTime)
        await Abi.methods.createAuction(auctionId, _initial_price, seller, itemUrl, startTime.toFixed(0), endTime.toFixed(0)).send({
          from: current,
        });
      } else {
        alert("Oops, Date is wrong")
      }

    } else {
      alert("connect wallet");
    }
  }

  const startAuction = async (e) => {
    e.preventDefault();
    if (isConnected && Abi) {
      try {
        await Abi.methods.startAuction().send({
          from: current,
        });
      } catch (err) {
        console.log(err)
      }
    } else {
      alert("connect wallet");
    }
  }
  const finishAuction = async (e) => {
    e.preventDefault();
    if (isConnected && Abi) {
      try {
        await Abi.methods.finishAuction().send({
          from: current,
        });
      } catch (err) {
        console.log(err)
      }
    } else {
      alert("connect wallet");
    }
  }

  const bid = async (e) => {
    e.preventDefault();
    if (isConnected && Abi) {
      console.log(balance)
      let _amount = web3.utils.toWei(bidAmount);
      console.log(_amount)
      if (Number(balance) >= Number(_amount)) {
        await Abi.methods.createBid(_amount).send({
          from: current,
        });
      } else {
        alert("Insufficient funds")
      }

    } else {
      alert("connect wallet");
    }
  }
  const closeBar = async (e) => {
    e.preventDefault();
    setPendingMessage('');
  }
  return (
    <>
      <nav className="navbar navbar-expand-sm navbar-dark" style={{ background: "black" }}>
        <div className="container-fluid">
          <ul className="navbar-nav me-auto">
            <li className="nav-item">
              {/* <a className="nav-link" href="https://whitepaper.zeustaking.finance/">WHITEPAPER</a> */}
            </li>
          </ul>
          <button className="btn btn-primary btn-lg btnd" style={{ background: "yellow", color: "black", border: "1px solid #fff" }} onClick={loadWeb3Modal}><i className="fas fa-wallet"></i> {connButtonText}</button>
        </div>
      </nav>
      <br />
      <div className="container">
        {pendingMessage !== '' ?
          <>
            <center>
              <div className="alert alert-warning alert-dismissible">
                <p onClick={closeBar} className="badge bg-dark" style={{ float: "right", cursor: "pointer" }}>X</p>
                {pendingMessage}
              </div>
            </center>
          </> :
          <></>
        }
        <div className="col-lg-12">
          <div className="card cardzeu">
            <div className="card-body">
              <h4><b>Auction</b></h4>
              <hr />
              <form onSubmit={createAuction}>
                <table className="table">
                  <tbody>
                    {owner && current && owner.toLowerCase() === current.toLowerCase() ? <>
                      <tr>
                        <td><h5>Auction ID</h5></td>
                        <td><h5>Initial price</h5></td>
                        <td><h5>Wallet of seller</h5></td>
                        <td><h5>URL of item</h5></td>
                        <td><h5>Start date</h5></td>
                        <td><h5>End date</h5></td>
                      </tr>
                      <tr>
                        <td><input
                          type="number"
                          className="form-control"
                          value={auctionId}
                          required
                          onChange={(e) => setAuctionId(e.target.value)}
                        /></td>
                        <td><input
                          type="number"
                          className="form-control"
                          value={initialPrice}
                          required
                          onChange={(e) => setInitialPrice(e.target.value)}
                        /></td>
                        <td><input
                          type="string"
                          className="form-control"
                          value={seller}
                          required
                          onChange={(e) => setSeller(e.target.value)}
                        /></td>
                        <td><input
                          type="string"
                          className="form-control"
                          value={itemUrl}
                          required
                          onChange={(e) => setItemUrl(e.target.value)}
                        /></td>
                        <td><input
                          type="date"
                          className="form-control"
                          value={startDate}
                          required
                          onChange={(e) => setStartDate(e.target.value)}
                        /></td>
                        <td><input
                          type="date"
                          className="form-control"
                          value={endDate}
                          required
                          onChange={(e) => setEndDate(e.target.value)}
                        /></td>
                      </tr>
                      <tr>
                        <td><button type="submit"
                          className="btn btn-primary btn-lg" style={{ background: "black", color: "#fff", border: "1px solid #fff" }}
                        >Create Auction</button></td>
                        <td><button onClick={startAuction}
                          className="btn btn-primary btn-lg" style={{ background: "black", color: "#fff", border: "1px solid #fff" }}
                        >Start Auction</button></td>
                        <td><button onClick={finishAuction}
                          className="btn btn-primary btn-lg" style={{ background: "black", color: "#fff", border: "1px solid #fff" }}
                        >Finish Auction</button></td>
                      </tr>
                    </> : <>
                      <tr>
                        <td><input
                          type="number"
                          className="form-control"
                          value={bidAmount}
                          onChange={(e) => setBidAmount(e.target.value)}
                          required
                        /></td>
                        <td>
                          {allowance > 0 ?
                            <>
                              <button onClick={bid}
                                className="btn btn-primary btn-lg" style={{ background: "black", color: "#fff", border: "1px solid #fff" }}>Bid</button>
                            </>
                            :
                            <>
                              <button className="btn btn-primary btn-lg" style={{ background: "black", color: "#fff", border: "1px solid #fff" }} onClick={approval}>APPROVE</button>
                            </>
                          }

                        </td>
                      </tr>
                      <tr>
                        <td><h5>Bidder</h5></td>
                        <td><h5>Amount</h5></td>
                      </tr>
                      {bids.length > 0 ?
                        bids.map((bid) =>
                          <tr>
                            <td><h5>{bid.bidder}</h5></td>
                            <td><h5>{bid.amount / 10e17}</h5></td>
                          </tr>
                        ) : <></>}
                    </>}

                  </tbody>
                </table>
              </form>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}

export default Interface;
